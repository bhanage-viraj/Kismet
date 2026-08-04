import ActivityKit
import AppIntents
import Foundation

/// Tap the compact Lock Screen banner → expand in place.
/// Must live in the **app** target: `LiveActivityIntent` runs in the app process
/// so `Activity.update` can see the running Live Activity.
struct ExpandMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Expand meetup"
	static var description = IntentDescription("Shows meetup details on the Lock Screen Live Activity.")
	static var isDiscoverable: Bool = false

	func perform() async throws -> some IntentResult {
		await MeetupLiveActivityController.setExpanded(true)
		return .result()
	}
}

/// Tap chevron on the expanded Lock Screen banner → collapse back to compact.
struct CollapseMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Collapse meetup"
	static var description = IntentDescription("Collapses the meetup Live Activity back to the compact banner.")
	static var isDiscoverable: Bool = false

	func perform() async throws -> some IntentResult {
		await MeetupLiveActivityController.setExpanded(false)
		return .result()
	}
}

/// Ends the meetup Live Activity and dismisses it from Lock Screen / Dynamic Island.
struct EndMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "End meetup"
	static var description = IntentDescription("Ends the meetup Live Activity.")
	static var isDiscoverable: Bool = false

	func perform() async throws -> some IntentResult {
		await MeetupLiveActivityController.end(dismissalPolicy: .immediate)
		return .result()
	}
}
