import ActivityKit
import AppIntents
import Foundation

/// Tap the compact Lock Screen banner → expand in place.
struct ExpandMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Expand meetup"
	static var description = IntentDescription("Shows meetup details on the Lock Screen Live Activity.")

	func perform() async throws -> some IntentResult {
		await Self.setExpanded(true)
		return .result()
	}

	static func setExpanded(_ expanded: Bool) async {
		for activity in Activity<MeetupActivityAttributes>.activities {
			var state = activity.content.state
			guard !state.isEnded else { continue }
			state.isExpanded = expanded
			let content = ActivityContent(
				state: state,
				staleDate: Date().addingTimeInterval(15 * 60)
			)
			await activity.update(content)
		}
	}
}

/// Tap chevron on the expanded Lock Screen banner → collapse back to compact.
struct CollapseMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Collapse meetup"
	static var description = IntentDescription("Collapses the meetup Live Activity back to the compact banner.")

	func perform() async throws -> some IntentResult {
		await ExpandMeetupLiveActivityIntent.setExpanded(false)
		return .result()
	}
}
