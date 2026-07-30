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

	func restore() async {
		phase = .bootstrapping
		guard KeychainStore.get(.accessToken) != nil, KeychainStore.get(.refreshToken) != nil else {
			phase = .signedOut
			user = nil
			return
		}

		do {
			try await loadMe()
			await checkAppleCredentialState()
		} catch {
			let refreshed = (try? await client.refreshTokens()) ?? false
			if refreshed {
				do {
					try await loadMe()
					await checkAppleCredentialState()
				} catch {
					KeychainStore.clearAuth()
					user = nil
					phase = .signedOut
				}
			} else {
				KeychainStore.clearAuth()
				user = nil
				phase = .signedOut
			}
		}
	}

	private func loadMe() async throws {
		let me: MeResponseDTO = try await client.get("/me")
		user = AuthResponseDTO.User(
			id: me.id,
			displayName: me.displayName,
			email: me.email,
			interests: me.interests,
			isNewUser: false,
			onboardingCompleted: me.onboardingCompleted
		)
		phase = me.onboardingCompleted ? .signedIn : .needsOnboarding
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

			var fullName: AppleAuthRequestDTO.FullName?
			if let nameComponents = credential.fullName {
				let given = nameComponents.givenName
				let family = nameComponents.familyName
				if given != nil || family != nil {
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
				let response: AuthResponseDTO = try await client.post(
					"/auth/apple",
					body: request,
					authorized: false
				)
				try KeychainStore.set(response.accessToken, for: .accessToken)
				try KeychainStore.set(response.refreshToken, for: .refreshToken)
				try KeychainStore.set(response.user.id, for: .userId)
				try KeychainStore.set(credential.user, for: .appleUserId)

				user = response.user
				phase = phaseAfterSignIn(onboardingCompleted: response.user.onboardingCompleted)
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
			updateUser(from: me)
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
			updateUser(from: me)
			phase = .signedIn
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func signOut() async {
		if KeychainStore.get(.accessToken) != nil {
			try? await client.postEmpty("/auth/logout")
		}
		KeychainStore.clearAuth()
		user = nil
		phase = .signedOut
	}

	func clearError() {
		lastErrorMessage = nil
	}

	private func updateUser(from me: MeResponseDTO) {
		user = AuthResponseDTO.User(
			id: me.id,
			displayName: me.displayName,
			email: me.email,
			interests: me.interests,
			isNewUser: false,
			onboardingCompleted: me.onboardingCompleted
		)
	}

	private func phaseAfterSignIn(onboardingCompleted: Bool) -> Phase {
		#if DEBUG
		// Repeat setup after an explicit sign-in, but not when restoring a valid session.
		return .needsOnboarding
		#else
		return onboardingCompleted ? .signedIn : .needsOnboarding
		#endif
	}

	private func checkAppleCredentialState() async {
		guard let appleUserId = KeychainStore.get(.appleUserId) else { return }
		let provider = ASAuthorizationAppleIDProvider()
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			provider.getCredentialState(forUserID: appleUserId) { state, _ in
				Task { @MainActor in
					switch state {
					case .revoked, .notFound:
						await self.signOut()
					default:
						break
					}
					continuation.resume()
				}
			}
		}
	}
}
