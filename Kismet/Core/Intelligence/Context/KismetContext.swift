import CoreLocation
import Foundation

struct UserContextSlice: Sendable {
	var userId: String?
	var displayName: String
	var interests: [String]
	var coordinate: CLLocationCoordinate2D
	var placeName: String?
	var freeUntil: Date?
	var isBusyNow: Bool
}

struct FriendPresence: Identifiable, Sendable {
	var id: String
	var displayName: String
	var coordinate: CLLocationCoordinate2D
	var presence: PresenceState
	var distanceMeters: CLLocationDistance
	var sharedInterests: [String]
	var freeUntil: Date?
	var freeFrom: Date?
	var lastSeenAt: Date?
	var locationAccuracy: Double?

	var walkingMinutes: Int {
		max(1, Int((distanceMeters / 80).rounded()))
	}
}

struct CalendarSlice: Sendable {
	var isBusyNow: Bool
	var nextFreeAt: Date?
	var freeUntil: Date?
}

struct MotionSlice: Sendable {
	var activity: MotionActivityKind
}

enum MotionActivityKind: String, Sendable {
	case unknown
	case stationary
	case walking
	case automotive
}

struct FocusSlice: Sendable {
	/// When true, hard-gate social suggestions.
	var blocksSocial: Bool
	var label: String?
}

struct KismetContext: Sendable {
	var generatedAt: Date
	var user: UserContextSlice
	var friends: [FriendPresence]
	var calendar: CalendarSlice
	var motion: MotionSlice
	var focus: FocusSlice
	var weather: WeatherSlice
	var learned: LearnedSlice

	/// Friends eligible for Suggestions / Siri (never Eclipse).
	var suggestionFriends: [FriendPresence] {
		friends.filter(\.presence.isSuggestionEligible)
	}
}
