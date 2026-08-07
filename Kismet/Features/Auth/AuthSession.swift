import AuthenticationServices
import Foundation
import Observation

@Observable
@MainActor
final class AuthSession {
	enum Phase: Equatable {
		case bootstrapping
		case signedOut
		case needsOnboarding
		case signedIn
	}

	private(set) var phase: Phase = .bootstrapping
	private(set) var user: AuthResponseDTO.User?
	private(set) var isSigningIn = false
	private(set) var isSavingOnboarding = false
	private(set) var lastErrorMessage: String?

	private let client: APIClient

	init(client: APIClient = .shared) {
		self.client = client
	}

	/// Name for chrome (map header, More). Never falls back to the raw email address.
	var preferredDisplayName: String {
		if let name = Self.normalizedName(user?.displayName) {
			return name
		}
		if let name = Self.normalizedName(KeychainStore.get(.cachedDisplayName)) {
			return name
		}
		return "You"
	}

	#if DEBUG
	/// Canvas / Preview host — skips Sign in with Apple and jumps to the signed-in app shell.
	static func previewSignedIn(
		displayName: String = "Preview User",
		interests: [String] = ["coffee", "maps"]
	) -> AuthSession {
		let session = AuthSession()
		session.user = AuthResponseDTO.User(
			id: "preview-user",
			displayName: displayName,
			email: "preview@indekismet.local",
			interests: interests,
			isNewUser: false,
			onboardingCompleted: true
		)
		session.phase = .signedIn
		return session
	}
	#endif

	func restore() async {
		phase = .bootstrapping
		guard KeychainStore.get(.accessToken) != nil, KeychainStore.get(.refreshToken) != nil else {
			phase = .signedOut
			user = nil
			return
		}

		// Cap splash wait: wake + /me should not block forever on a cold Render instance.
		let restored = await withTaskGroup(of: Bool.self) { group in
			group.addTask { @MainActor in
				await self.client.wakeServer()
				guard !Task.isCancelled else { return false }
				do {
					try await self.loadMe(allowColdStart: true)
					return true
				} catch is CancellationError {
					return false
				} catch {
					guard !Task.isCancelled else { return false }
					let refreshed = (try? await self.client.refreshTokens()) ?? false
					if refreshed {
						do {
							try await self.loadMe(allowColdStart: true)
							return true
						} catch is CancellationError {
							return false
						} catch {
							self.endRestore(after: error)
							return self.phase == .signedIn
						}
					} else {
						self.endRestore(after: error)
						return self.phase == .signedIn
					}
				}
			}
			group.addTask {
				try? await Task.sleep(for: .seconds(18))
				return false
			}
			let first = await group.next() ?? false
			group.cancelAll()
			return first
		}

		if !restored, phase == .bootstrapping {
			endRestore(after: APIClientError.invalidResponse)
		}

		guard phase == .signedIn || phase == .needsOnboarding else { return }

		// Don't block the splash on crypto publish or Apple credential checks.
		Task { await publishEncryptionKeyIfNeeded() }
		Task { await checkAppleCredentialState() }
	}

	/// `refreshTokens()` drops the stored credentials when the server rejects them, so
	/// a surviving refresh token means restore failed for some other reason — an
	/// unreachable server, most likely. Keep it: enter the app shell offline so one
	/// bad launch doesn't force a full sign-in loop.
	private func endRestore(after error: Error) {
		guard KeychainStore.get(.refreshToken) != nil,
		      let userId = KeychainStore.get(.userId)
		else {
			clearAuthState()
			return
		}
		user = AuthResponseDTO.User(
			id: userId,
			displayName: Self.normalizedName(KeychainStore.get(.cachedDisplayName)),
			email: nil,
			interests: [],
			isNewUser: false,
			onboardingCompleted: true
		)
		phase = .signedIn
		lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
	}

	private func loadMe(allowColdStart: Bool = false) async throws {
		let me: MeResponseDTO = try await client.request(
			method: "GET",
			path: "/me",
			body: nil as String?,
			authorized: true,
			allowColdStart: allowColdStart
		)
		applyUser(from: me, isNewUser: false)
		phase = me.onboardingCompleted ? .signedIn : .needsOnboarding
		await syncDisplayNameIfNeeded()
	}

	func handleSignInCompletion(_ result: Result<ASAuthorization, Error>) async {
		lastErrorMessage = nil

		switch result {
		case .failure(let error):
			if let authError = error as? ASAuthorizationError, authError.code == .canceled {
				return
			}
			lastErrorMessage = error.localizedDescription
		case .success(let authorization):
			guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
				lastErrorMessage = "Unexpected Apple credential."
				return
			}
			guard let tokenData = credential.identityToken,
			      let identityToken = String(data: tokenData, encoding: .utf8) else {
				lastErrorMessage = "Missing Apple identity token."
				return
			}

			isSigningIn = true
			defer { isSigningIn = false }

			cacheAppleDisplayName(from: credential.fullName)

			var fullName: AppleAuthRequestDTO.FullName?
			if let nameComponents = credential.fullName {
				let given = nameComponents.givenName
				let family = nameComponents.familyName
				if Self.normalizedName(given) != nil || Self.normalizedName(family) != nil {
					fullName = .init(givenName: given, familyName: family)
				}
			}

			let request = AppleAuthRequestDTO(
				identityToken: identityToken,
				fullName: fullName,
				email: credential.email,
				interests: []
			)

			do {
				// Free Render instances sleep when idle; wake + long timeout + retries
				// cover the ~2 min cold start that was failing App Review sign-in.
				await client.wakeServer()
				let response: AuthResponseDTO = try await client.requestWithTransientRetry(
					method: "POST",
					path: "/auth/apple",
					body: request,
					authorized: false,
					attempts: 3
				)
				try KeychainStore.set(response.accessToken, for: .accessToken)
				try KeychainStore.set(response.refreshToken, for: .refreshToken)
				try KeychainStore.set(response.user.id, for: .userId)
				try KeychainStore.set(credential.user, for: .appleUserId)

				user = response.user
				if let name = Self.normalizedName(response.user.displayName) {
					try? KeychainStore.set(name, for: .cachedDisplayName)
				}
				phase = phaseAfterSignIn(onboardingCompleted: response.user.onboardingCompleted)
				await syncDisplayNameIfNeeded()
				await publishEncryptionKeyIfNeeded()
			} catch {
				lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			}
		}
	}

	func saveInterests(_ interests: [String]) async -> Bool {
		isSavingOnboarding = true
		lastErrorMessage = nil
		defer { isSavingOnboarding = false }

		do {
			let me: MeResponseDTO = try await client.request(
				method: "POST",
				path: "/me/interests",
				body: InterestsRequestDTO(interests: interests),
				authorized: true
			)
			applyUser(from: me, isNewUser: false)
			return true
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return false
		}
	}

	func completeOnboarding(_ availability: AvailabilitySetupRequestDTO) async {
		isSavingOnboarding = true
		lastErrorMessage = nil
		defer { isSavingOnboarding = false }

		do {
			let me: MeResponseDTO = try await client.request(
				method: "POST",
				path: "/me/onboarding-complete",
				body: availability,
				authorized: true
			)
			applyUser(from: me, isNewUser: false)
			phase = .signedIn
			await syncDisplayNameIfNeeded()
			await publishEncryptionKeyIfNeeded()
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func signOut() async {
		if KeychainStore.get(.accessToken) != nil {
			try? await client.postEmpty("/auth/logout")
		}
		await CryptoBox.shared.clearLocalKeys()
		clearAuthState()
	}

	func clearError() {
		lastErrorMessage = nil
	}

	private func applyUser(from me: MeResponseDTO, isNewUser: Bool) {
		user = AuthResponseDTO.User(
			id: me.id,
			displayName: Self.normalizedName(me.displayName),
			email: me.email,
			interests: me.interests,
			isNewUser: isNewUser,
			onboardingCompleted: me.onboardingCompleted
		)
		if let name = Self.normalizedName(me.displayName) {
			try? KeychainStore.set(name, for: .cachedDisplayName)
		}
	}

	/// If the server never got Apple's one-time name, push the locally cached name up.
	private func syncDisplayNameIfNeeded() async {
		guard Self.normalizedName(user?.displayName) == nil,
		      let cached = Self.normalizedName(KeychainStore.get(.cachedDisplayName))
		else {
			return
		}

		do {
			let me: MeResponseDTO = try await client.put(
				"/me/display-name",
				body: DisplayNameRequestDTO(displayName: cached)
			)
			applyUser(from: me, isNewUser: false)
		} catch {
			// Keep showing the cached name locally even if sync fails.
		}
	}

	private func cacheAppleDisplayName(from nameComponents: PersonNameComponents?) {
		guard let nameComponents else { return }
		let formatter = PersonNameComponentsFormatter()
		let formatted = formatter.string(from: nameComponents)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let name = Self.normalizedName(formatted) else { return }
		try? KeychainStore.set(name, for: .cachedDisplayName)
	}

	private func publishEncryptionKeyIfNeeded() async {
		do {
			_ = try await CryptoBox.shared.ensurePublished(using: client)
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription
				?? error.localizedDescription
		}
	}

	private func clearAuthState() {
		KeychainStore.clearAuth()
		user = nil
		phase = .signedOut
	}

	private func phaseAfterSignIn(onboardingCompleted: Bool) -> Phase {
		onboardingCompleted ? .signedIn : .needsOnboarding
	}

	private func checkAppleCredentialState() async {
		guard let appleUserId = KeychainStore.get(.appleUserId) else { return }
		let provider = ASAuthorizationAppleIDProvider()
		await withTaskGroup(of: Void.self) { group in
			group.addTask {
				await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
					provider.getCredentialState(forUserID: appleUserId) { state, _ in
						Task { @MainActor in
							switch state {
							case .revoked:
								await self.signOut()
							default:
								// `.notFound` also means "this credential isn't associated with
								// this App ID", which is what a bundle identifier change looks
								// like. Too weak a signal to tear down a session the server
								// still accepts.
								break
							}
							continuation.resume()
						}
					}
				}
			}
			group.addTask {
				try? await Task.sleep(for: .seconds(3))
			}
			await group.next()
			group.cancelAll()
		}
	}

	private static func normalizedName(_ value: String?) -> String? {
		guard let value else { return nil }
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		// Guard against older clients / bad data that stored an email in displayName.
		if trimmed.contains("@") { return nil }
		return trimmed
	}
}
