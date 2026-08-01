import Foundation
import Observation

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
}
