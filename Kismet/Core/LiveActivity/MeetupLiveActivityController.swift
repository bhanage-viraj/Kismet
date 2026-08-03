import ActivityKit
import CoreLocation
import Foundation

/// Starts / updates / ends a meetup Live Activity from the main app.
/// Lock Screen always starts compact (`isExpanded: false`); the user taps to expand.
/// ETA / distance refresh via `MeetupLiveActivityTracker` as location updates arrive.
@MainActor
enum MeetupLiveActivityController {
	@discardableResult
	static func start(
		attributes: MeetupActivityAttributes,
		state: MeetupActivityAttributes.ContentState
	) async throws -> Activity<MeetupActivityAttributes> {
		guard ActivityAuthorizationInfo().areActivitiesEnabled else {
			throw ControllerError.disabled
		}

		for activity in Activity<MeetupActivityAttributes>.activities {
			await activity.end(nil, dismissalPolicy: .immediate)
		}

		var initial = state
		initial.isExpanded = false
		initial.isEnded = false

		let content = ActivityContent(state: initial, staleDate: Date().addingTimeInterval(15 * 60))
		return try Activity.request(
			attributes: attributes,
			content: content,
			pushType: nil
		)
	}

	/// Starts a meetup Live Activity and seeds ETA from the current location + meet time.
	@discardableResult
	static func start(
		meetupID: String,
		title: String,
		venueName: String,
		systemImage: String,
		participants: [MeetupActivityAttributes.Participant],
		venueCoordinate: CLLocationCoordinate2D?,
		meetAt: Date?,
		currentLocation: CLLocation?
	) async throws -> Activity<MeetupActivityAttributes> {
		var initialDistance: Double?
		var state = MeetupActivityAttributes.ContentState.preview

		if let venueCoordinate {
			let seeded = MeetupJourneyMetrics.initialSnapshot(
				from: currentLocation,
				venueLatitude: venueCoordinate.latitude,
				venueLongitude: venueCoordinate.longitude,
				meetAt: meetAt
			)
			state = MeetupActivityAttributes.ContentState(
				etaText: seeded.snapshot.etaText,
				distanceText: seeded.snapshot.distanceText,
				progress: seeded.snapshot.progress,
				isEnded: false,
				isExpanded: false
			)
			initialDistance = seeded.initialDistance
		} else if let meetAt {
			let minutes = max(0, Int(ceil(meetAt.timeIntervalSinceNow / 60)))
			state = MeetupActivityAttributes.ContentState(
				etaText: minutes <= 0 ? "Now" : "\(minutes) min",
				distanceText: "—",
				progress: 0,
				isEnded: false,
				isExpanded: false
			)
		} else {
			state = MeetupActivityAttributes.ContentState(
				etaText: "—",
				distanceText: "—",
				progress: 0,
				isEnded: false,
				isExpanded: false
			)
		}

		let attributes = MeetupActivityAttributes(
			meetupID: meetupID,
			title: title,
			venueName: venueName,
			systemImage: systemImage,
			participants: participants,
			venueLatitude: venueCoordinate?.latitude,
			venueLongitude: venueCoordinate?.longitude,
			meetAt: meetAt,
			initialDistanceMeters: initialDistance
		)

		return try await start(attributes: attributes, state: state)
	}

	static func update(
		etaText: String,
		distanceText: String,
		progress: Double
	) async {
		for activity in Activity<MeetupActivityAttributes>.activities {
			var state = activity.content.state
			state.etaText = etaText
			state.distanceText = distanceText
			state.progress = progress
			state.isEnded = false
			let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))
			await activity.update(content)
		}
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

	static func end(dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
		let final = ActivityContent(
			state: MeetupActivityAttributes.ContentState.ended,
			staleDate: nil
		)
		for activity in Activity<MeetupActivityAttributes>.activities {
			await activity.end(final, dismissalPolicy: dismissalPolicy)
		}
	}

	enum ControllerError: Error {
		case disabled
	}
}
