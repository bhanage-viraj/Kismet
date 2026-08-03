import ActivityKit
import CoreLocation
import Foundation

/// Pushes Live Activity ContentState updates as the user moves toward the meetup pin.
@MainActor
enum MeetupLiveActivityTracker {
	private static var lastPushAt: Date?
	private static let minPushInterval: TimeInterval = 12

	static var hasActiveMeetup: Bool {
		!Activity<MeetupActivityAttributes>.activities.isEmpty
	}

	/// Call from `VisitLocationManager` on each accepted location fix.
	static func handleLocationUpdate(_ location: CLLocation) {
		guard hasActiveMeetup else { return }

		if let lastPushAt, Date().timeIntervalSince(lastPushAt) < minPushInterval {
			return
		}

		Task {
			await push(from: location)
		}
	}

	static func push(from location: CLLocation, force: Bool = false) async {
		guard hasActiveMeetup else { return }
		if !force, let lastPushAt, Date().timeIntervalSince(lastPushAt) < minPushInterval {
			return
		}

		for activity in Activity<MeetupActivityAttributes>.activities {
			let attrs = activity.attributes
			guard let lat = attrs.venueLatitude, let lon = attrs.venueLongitude else { continue }

			let snap = MeetupJourneyMetrics.snapshot(
				from: location,
				venueLatitude: lat,
				venueLongitude: lon,
				meetAt: attrs.meetAt,
				initialDistanceMeters: attrs.initialDistanceMeters
			)

			await MeetupLiveActivityController.update(
				etaText: snap.etaText,
				distanceText: snap.distanceText,
				progress: snap.progress
			)
		}

		lastPushAt = .now
	}
}
