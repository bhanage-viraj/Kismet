import ActivityKit
import Foundation

/// Generic Live Activity for any in-progress meetup / hangout / shared activity.
/// Keep in sync with `Kismet/Core/LiveActivity/MeetupActivityAttributes.swift`.
struct MeetupActivityAttributes: ActivityAttributes {
	struct Participant: Codable, Hashable, Identifiable, Sendable {
		var id: String
		var displayName: String
		var initials: String
		var status: FriendStatus
		var isYou: Bool
		var avatarFileName: String? = nil

		enum FriendStatus: String, Codable, Hashable, Sendable {
			case free
			case busy
			case nearby
		}
	}

	struct ContentState: Codable, Hashable, Sendable {
		var etaText: String
		var distanceText: String
		/// Journey progress from walker → pin, 0...1.
		var progress: Double
		var isEnded: Bool
		/// Lock Screen starts compact; tap expands in place.
		var isExpanded: Bool

		static let preview = ContentState(
			etaText: "5 min",
			distanceText: "350 m",
			progress: 0.72,
			isEnded: false,
			isExpanded: false
		)

		static let previewExpanded = ContentState(
			etaText: "5 min",
			distanceText: "350 m",
			progress: 0.72,
			isEnded: false,
			isExpanded: true
		)

		static let ended = ContentState(
			etaText: "—",
			distanceText: "—",
			progress: 1,
			isEnded: true,
			isExpanded: false
		)
	}

	var meetupID: String
	var title: String
	var venueName: String
	var systemImage: String
	var participants: [Participant]
	/// Meetup pin — used to refresh ETA / distance as the user moves.
	var venueLatitude: Double? = nil
	var venueLongitude: Double? = nil
	/// Scheduled meet time — blends into ETA when close to the venue or waiting.
	var meetAt: Date? = nil
	/// Distance when the activity started — drives journey progress 0→1.
	var initialDistanceMeters: Double? = nil

	var headline: String {
		venueName.isEmpty ? title : venueName
	}

	var venueCoordinate: (lat: Double, lon: Double)? {
		guard let venueLatitude, let venueLongitude else { return nil }
		return (venueLatitude, venueLongitude)
	}

	static let preview = MeetupActivityAttributes(
		meetupID: "preview-coffee",
		title: "Coffee catch-up",
		venueName: "Third Wave Coffee",
		systemImage: "cup.and.saucer.fill",
		participants: [
			Participant(id: "aarav", displayName: "Aarav", initials: "A", status: .free, isYou: false),
			Participant(id: "neha", displayName: "Neha", initials: "N", status: .busy, isYou: false),
			Participant(id: "you", displayName: "You", initials: "Y", status: .free, isYou: true),
		],
		venueLatitude: 12.9716,
		venueLongitude: 77.6412,
		meetAt: Date().addingTimeInterval(5 * 60),
		initialDistanceMeters: 350
	)

	static let previewWalk = MeetupActivityAttributes(
		meetupID: "preview-walk",
		title: "Evening walk",
		venueName: "Cubbon Park",
		systemImage: "figure.walk",
		participants: preview.participants,
		venueLatitude: 12.9763,
		venueLongitude: 77.5929,
		meetAt: Date().addingTimeInterval(12 * 60),
		initialDistanceMeters: 900
	)
}

extension MeetupActivityAttributes.Participant {
	var widgetStatus: WidgetAppGroup.WidgetStatus {
		switch status {
		case .free: .free
		case .busy: .busy
		case .nearby: .nearby
		}
	}
}
