import ActivityKit
import AppIntents
import Foundation

/// Tap the compact Lock Screen banner → expand in place.
/// Keep in sync with `Kismet/Core/LiveActivity/MeetupLiveActivityIntents.swift`.
/// Widget target needs this type for `Button(intent:)`; `LiveActivityIntent.perform()`
/// runs in the **app** process (see app-target copy).
struct ExpandMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Expand meetup"
	static var description = IntentDescription("Shows meetup details on the Lock Screen Live Activity.")
	static var isDiscoverable: Bool = false

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
	static var isDiscoverable: Bool = false

	func perform() async throws -> some IntentResult {
		await ExpandMeetupLiveActivityIntent.setExpanded(false)
		return .result()
	}
}

/// Ends the meetup Live Activity. Keep in sync with the app-target intent.
struct EndMeetupLiveActivityIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "End meetup"
	static var description = IntentDescription("Ends the meetup Live Activity.")
	static var isDiscoverable: Bool = false

	func perform() async throws -> some IntentResult {
		let final = ActivityContent(
			state: MeetupActivityAttributes.ContentState.ended,
			staleDate: nil
		)
		for activity in Activity<MeetupActivityAttributes>.activities {
			await activity.end(final, dismissalPolicy: .immediate)
		}
		return .result()
	}
}
