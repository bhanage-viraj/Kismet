import Foundation
import Observation

/// On-device allowlist for Friends Only presence.
/// `nil` = all friends (legacy default). Non-nil = precise LOCATION only for those ids;
/// everyone else gets an Eclipse-style hide overwrite.
@Observable
@MainActor
final class FriendsOnlyVisibilityStore {
	private static let defaultsKey = "kismet.friendsOnly.visibleFriendIds"
	private static let customizedKey = "kismet.friendsOnly.customized"

	/// When `nil`, every friend with a key receives precise Friends Only location.
	/// When set (including empty), only listed ids receive precise; others get Eclipse hide.
	private(set) var visibleFriendIds: Set<String>?

	var isCustomized: Bool {
		visibleFriendIds != nil
	}

	init() {
		if UserDefaults.standard.bool(forKey: Self.customizedKey),
		   let stored = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [String] {
			visibleFriendIds = Set(stored)
		} else {
			visibleFriendIds = nil
		}
	}

	func replace(with ids: Set<String>) {
		visibleFriendIds = ids
		UserDefaults.standard.set(true, forKey: Self.customizedKey)
		UserDefaults.standard.set(Array(ids), forKey: Self.defaultsKey)
	}

	func resetToAllFriends() {
		visibleFriendIds = nil
		UserDefaults.standard.set(false, forKey: Self.customizedKey)
		UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
	}

	/// Whether this friend should receive precise Friends Only coordinates.
	func allowsPrecise(for friendUserId: String) -> Bool {
		guard let visibleFriendIds else { return true }
		return visibleFriendIds.contains(friendUserId)
	}
}
