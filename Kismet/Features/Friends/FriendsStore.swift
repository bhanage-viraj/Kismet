import Foundation
import Observation

extension Notification.Name {
	/// Posted after Bump successfully persists a friendship. UserInfo keys:
	/// `peerUserId`, `peerDisplayName`, `peerPublicKey` (all String).
	static let bumpPairingSucceeded = Notification.Name("kismet.bump.pairingSucceeded")
}

@Observable
@MainActor
final class FriendsStore {
	private(set) var friends: [FriendSummaryDTO] = []
	private(set) var activeInvite: InviteCodeResponseDTO?
	private(set) var isLoading = false
	private(set) var isMutating = false
	private(set) var lastErrorMessage: String?
	private(set) var lastSuccessMessage: String?
	/// Bumps whenever the friend graph changes so the map can refresh.
	private(set) var graphRevision: Int = 0

	private let client: APIClient

	init(client: APIClient = .shared) {
		self.client = client
	}

	#if DEBUG
	static func preview(friends: [FriendSummaryDTO] = []) -> FriendsStore {
		let store = FriendsStore()
		store.friends = friends
		return store
	}
	#endif

	func refresh() async {
		isLoading = true
		lastErrorMessage = nil
		defer { isLoading = false }

		do {
			let response: FriendListResponseDTO = try await client.get("/friends")
			friends = response.friends.sorted {
				($0.displayName ?? $0.userId).localizedCaseInsensitiveCompare($1.displayName ?? $1.userId)
					== .orderedAscending
			}
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func createInvite() async {
		isMutating = true
		lastErrorMessage = nil
		lastSuccessMessage = nil
		defer { isMutating = false }

		do {
			let invite: InviteCodeResponseDTO = try await client.post("/friends/invite")
			activeInvite = invite
			lastSuccessMessage = "Invite code ready — share it before it expires."
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	@discardableResult
	func redeem(code: String) async -> Bool {
		let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			lastErrorMessage = "Enter an invite code."
			return false
		}

		isMutating = true
		lastErrorMessage = nil
		lastSuccessMessage = nil
		defer { isMutating = false }

		do {
			let friend: FriendSummaryDTO = try await client.post(
				"/friends/redeem",
				body: RedeemInviteRequestDTO(inviteCode: trimmed)
			)
			await refresh()
			graphRevision += 1
			let name = friend.displayName ?? "your friend"
			lastSuccessMessage = "Connected with \(name)."
			return true
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return false
		}
	}

	/// Persists a friendship after local Bump consent + key exchange. Treats HTTP 409
	/// (already connected) as success so dual-device calls stay idempotent.
	@discardableResult
	func pairViaBump(peerUserId: String, peerPublicKey: String?) async -> FriendSummaryDTO? {
		isMutating = true
		lastErrorMessage = nil
		lastSuccessMessage = nil
		defer { isMutating = false }

		do {
			let friend: FriendSummaryDTO = try await client.post(
				"/friends/pair",
				body: BumpPairRequestDTO(peerUserId: peerUserId, peerPublicKey: peerPublicKey)
			)
			await refresh()
			graphRevision += 1
			postPairingSucceeded(friend)
			let name = friend.displayName ?? "your friend"
			lastSuccessMessage = "Connected with \(name)."
			return friend
		} catch APIClientError.httpStatus(409, _) {
			await refresh()
			graphRevision += 1
			if let existing = friends.first(where: { $0.userId == peerUserId }) {
				postPairingSucceeded(existing)
				lastSuccessMessage = "Already friends with \(existing.displayName ?? "this person")."
				return existing
			}
			lastSuccessMessage = "Already connected."
			postPairingSucceeded(
				FriendSummaryDTO(
					pairId: "",
					userId: peerUserId,
					displayName: nil,
					publicKey: peerPublicKey,
					keyVersion: 1,
					status: "ACTIVE",
					connectedVia: "BUMP",
					since: nil,
					initiatedByMe: true
				)
			)
			return nil
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return nil
		}
	}

	/// Acceptor side after pairAck — refresh list and notify observers without calling pair again.
	func noteRemoteBumpPairing(peerUserId: String, peerDisplayName: String, peerPublicKey: String) async {
		await refresh()
		graphRevision += 1
		NotificationCenter.default.post(
			name: .bumpPairingSucceeded,
			object: nil,
			userInfo: [
				"peerUserId": peerUserId,
				"peerDisplayName": peerDisplayName,
				"peerPublicKey": peerPublicKey,
			]
		)
	}

	func revoke(friendUserId: String) async {
		isMutating = true
		lastErrorMessage = nil
		lastSuccessMessage = nil
		defer { isMutating = false }

		do {
			try await client.deleteEmpty("/friends/\(friendUserId)")
			friends.removeAll { $0.userId == friendUserId }
			graphRevision += 1
			lastSuccessMessage = "Friend removed."
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func clearMessages() {
		lastErrorMessage = nil
		lastSuccessMessage = nil
	}

	func reset() {
		friends = []
		activeInvite = nil
		lastErrorMessage = nil
		lastSuccessMessage = nil
		isLoading = false
		isMutating = false
	}

	func isFriend(userId: String) -> Bool {
		friends.contains { $0.userId == userId }
	}

	private func postPairingSucceeded(_ friend: FriendSummaryDTO) {
		NotificationCenter.default.post(
			name: .bumpPairingSucceeded,
			object: nil,
			userInfo: [
				"peerUserId": friend.userId,
				"peerDisplayName": friend.displayName ?? friend.userId,
				"peerPublicKey": friend.publicKey ?? "",
			]
		)
	}
}
