import Foundation

struct MeetupEventSnapshot: Sendable, Hashable {
	var id: UUID
	var friendUserId: String
	var friendDisplayName: String
	var startedAt: Date
	var endedAt: Date?
	var venueName: String?
	var venueCategory: VenueCategory
	var source: MeetupSource
	var outcome: MeetupOutcome
}

struct SuggestionFeedbackSnapshot: Sendable, Hashable {
	var id: UUID
	var friendUserId: String
	var createdAt: Date
	var action: SuggestionFeedbackAction
	var reasonCodes: [String]
}

struct FriendLearnedStats: Sendable, Hashable {
	var friendUserId: String
	var friendDisplayName: String
	var completedCount: Int
	/// Recency-weighted affinity in roughly 0...1+.
	var affinityScore: Double
	var hoursSinceLastCompletedMeetup: Double?
	var dismissCount: Int
	var ctaCount: Int
	var upCount: Int
	var downCount: Int
	var preferredCategories: [VenueCategory]

	var isOnCooldown: Bool {
		guard let hours = hoursSinceLastCompletedMeetup else { return false }
		return hours < 18
	}
}

struct LearnedSlice: Sendable, Hashable {
	var summaryText: String
	var preferredHours: [Int]
	var preferredCategories: [VenueCategory]
	var topFriendIds: [String]
	var byFriend: [String: FriendLearnedStats]
	var completedMeetupCount: Int
	var updatedAt: Date

	static let empty = LearnedSlice(
		summaryText: "",
		preferredHours: [],
		preferredCategories: [],
		topFriendIds: [],
		byFriend: [:],
		completedMeetupCount: 0,
		updatedAt: .distantPast
	)

	func stats(for friendUserId: String) -> FriendLearnedStats? {
		byFriend[friendUserId]
	}

	var hasSignal: Bool {
		completedMeetupCount > 0 || !byFriend.isEmpty || !summaryText.isEmpty
	}
}
