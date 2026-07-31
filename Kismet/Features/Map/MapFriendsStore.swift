import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class MapFriendsStore {
	private(set) var friends: [MapPerson] = []
	private(set) var selectedFriendID: String?

	var selectedFriend: MapPerson? {
		guard let selectedFriendID else { return nil }
		return friends.first { $0.id == selectedFriendID }
	}

	func refresh(around coordinate: CLLocationCoordinate2D?) {
		let origin = coordinate ?? MockFriendsProvider.fallbackCoordinate
		friends = MockFriendsProvider.friends(around: origin)
	}

	func select(_ friendID: String?) {
		selectedFriendID = friendID
	}

	func clearSelection() {
		selectedFriendID = nil
	}
}
