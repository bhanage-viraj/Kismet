import Foundation

/// Empty-only sample entries for Xcode `#Preview`. Live widgets never fall back to this.
enum WidgetPreviewData {
	static let emptySnapshot = WidgetAppGroup.SuggestionSnapshot(
		schemaVersion: WidgetAppGroup.schemaVersion,
		updatedAt: .now,
		headline: "No friends nearby",
		friendCountNearby: 0,
		cards: [],
		featuredMeetup: nil,
		userLatitude: nil,
		userLongitude: nil
	)

	static var emptyEntry: FriendAvailabilityEntry {
		FriendAvailabilityEntry(date: .now, snapshot: emptySnapshot)
	}
}
