import Testing
@testable import Kismet

@MainActor
struct FriendsOnlyVisibilityStoreTests {
	@Test func defaultAllowsEveryone() {
		let store = FriendsOnlyVisibilityStore()
		store.resetToAllFriends()
		#expect(store.allowsPrecise(for: "a"))
		#expect(store.allowsPrecise(for: "b"))
		#expect(!store.isCustomized)
	}

	@Test func customizedAllowlistFilters() {
		let store = FriendsOnlyVisibilityStore()
		store.replace(with: ["a", "c"])
		#expect(store.allowsPrecise(for: "a"))
		#expect(!store.allowsPrecise(for: "b"))
		#expect(store.allowsPrecise(for: "c"))
		#expect(store.isCustomized)
	}

	@Test func emptyAllowlistHidesEveryone() {
		let store = FriendsOnlyVisibilityStore()
		store.replace(with: [])
		#expect(!store.allowsPrecise(for: "a"))
		#expect(store.isCustomized)
	}
}
