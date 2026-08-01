import CoreLocation
import Foundation
import Testing
@testable import Kismet

struct LearnedRankingTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	@Test func affinityBoostsFriendWithPastHangouts() {
		let alex = friend(id: "alex", name: "Alex", meters: 200)
		let sam = friend(id: "sam", name: "Sam", meters: 200)

		let learned = LearnedFeatureBuilder().build(
			meetups: [
				MeetupEventSnapshot(
					id: UUID(),
					friendUserId: "alex",
					friendDisplayName: "Alex",
					startedAt: Date().addingTimeInterval(-3 * 24 * 3600),
					endedAt: nil,
					venueName: "Blue Tokai",
					venueCategory: .coffee,
					source: .pulse,
					outcome: .completed
				),
				MeetupEventSnapshot(
					id: UUID(),
					friendUserId: "alex",
					friendDisplayName: "Alex",
					startedAt: Date().addingTimeInterval(-10 * 24 * 3600),
					endedAt: nil,
					venueName: "Cafe",
					venueCategory: .coffee,
					source: .manual,
					outcome: .completed
				)
			],
			feedback: []
		)

		let ranked = OpportunityRanker().rank(
			context: makeContext(friends: [alex, sam], learned: learned, hour: 15)
		)

		#expect(ranked.first?.friend.id == "alex")
		#expect(ranked.first?.reasonCodes.contains(.pastHangouts) == true)
	}

	@Test func cooldownPenalizesRecentMeetup() {
		let alex = friend(id: "alex", name: "Alex", meters: 150)
		let sam = friend(id: "sam", name: "Sam", meters: 400)

		let learned = LearnedFeatureBuilder().build(
			meetups: [
				MeetupEventSnapshot(
					id: UUID(),
					friendUserId: "alex",
					friendDisplayName: "Alex",
					startedAt: Date().addingTimeInterval(-2 * 3600),
					endedAt: Date().addingTimeInterval(-1 * 3600),
					venueName: "Coffee",
					venueCategory: .coffee,
					source: .pulse,
					outcome: .completed
				)
			],
			feedback: []
		)

		let ranked = OpportunityRanker().rank(
			context: makeContext(friends: [alex, sam], learned: learned, hour: 15)
		)

		#expect(ranked.contains { $0.friend.id == "alex" })
		let alexRank = ranked.first { $0.friend.id == "alex" }
		#expect(alexRank?.reasonCodes.contains(.metRecently) == true)
		#expect(ranked.first?.friend.id == "sam")
	}

	@Test func preferredSlotAddsUsualMeetupTimeReason() {
		let alex = friend(id: "alex", name: "Alex", meters: 250)
		var learned = LearnedSlice.empty
		learned.preferredHours = [15]
		learned.byFriend = [
			"alex": FriendLearnedStats(
				friendUserId: "alex",
				friendDisplayName: "Alex",
				completedCount: 1,
				affinityScore: 0.5,
				hoursSinceLastCompletedMeetup: 48,
				dismissCount: 0,
				ctaCount: 1,
				upCount: 0,
				downCount: 0,
				preferredCategories: [.coffee]
			)
		]
		learned.completedMeetupCount = 1

		let ranked = OpportunityRanker().rank(
			context: makeContext(friends: [alex], learned: learned, hour: 15)
		)

		#expect(ranked.first?.reasonCodes.contains(.usualMeetupTime) == true)
		let slot = PreferredSlotSignal().contribution(
			opportunity: RawOpportunity(friend: alex),
			context: makeContext(friends: [alex], learned: learned, hour: 15)
		)
		#expect(slot > 0)
	}

	@Test func dismissPenaltyLowersScore() {
		let alex = friend(id: "alex", name: "Alex", meters: 200)
		var learned = LearnedSlice.empty
		learned.byFriend = [
			"alex": FriendLearnedStats(
				friendUserId: "alex",
				friendDisplayName: "Alex",
				completedCount: 0,
				affinityScore: 0,
				hoursSinceLastCompletedMeetup: nil,
				dismissCount: 3,
				ctaCount: 0,
				upCount: 0,
				downCount: 0,
				preferredCategories: []
			)
		]

		let penalty = DismissPenaltySignal().contribution(
			opportunity: RawOpportunity(friend: alex),
			context: makeContext(friends: [alex], learned: learned, hour: 12)
		)
		#expect(penalty < 0)
	}

	// MARK: - Helpers

	private func friend(id: String, name: String, meters: Double) -> FriendPresence {
		FriendPresence(
			id: id,
			displayName: name,
			coordinate: origin,
			presence: .available,
			distanceMeters: meters,
			sharedInterests: ["coffee"],
			freeUntil: nil,
			freeFrom: nil,
			lastSeenAt: nil,
			locationAccuracy: nil
		)
	}

	private func makeContext(
		friends: [FriendPresence],
		learned: LearnedSlice,
		hour: Int
	) -> KismetContext {
		var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
		components.hour = hour
		components.minute = 0
		let date = Calendar.current.date(from: components) ?? Date()

		return KismetContext(
			generatedAt: date,
			user: UserContextSlice(
				userId: "me",
				displayName: "You",
				interests: ["coffee"],
				coordinate: origin,
				placeName: "Koramangala",
				freeUntil: nil,
				isBusyNow: false
			),
			friends: friends,
			calendar: CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: nil),
			motion: MotionSlice(activity: .walking),
			focus: FocusSlice(blocksSocial: false, label: nil),
			learned: learned
		)
	}
}
