import CoreLocation
import Foundation

struct RankedOpportunity: Sendable, Identifiable {
	var id: String { friend.id }
	var friend: FriendPresence
	var score: Double
	var reasonCodes: [ExplainCode]
	var learnedStats: FriendLearnedStats?
}

enum ExplainCode: String, Sendable, Hashable {
	case bothFree
	case nearbyWalk
	case sharedInterest
	case freeSoon
	case approximateNearby
	case goodTimeForCoffee
	case pastHangouts
	case usualMeetupTime
	case metRecently
}

struct OpportunityRanker: Sendable {
	var maxDistanceMeters: CLLocationDistance = 3_000
	var topK: Int = 3
	var signals: [any RankingSignal] = [
		AvailabilitySignal(),
		DistanceSignal(),
		SharedInterestSignal(),
		TimeOfDaySignal(),
		MotionSignal(),
		FriendAffinitySignal(),
		RecentMeetupCooldownSignal(),
		PreferredSlotSignal(),
		DismissPenaltySignal()
	]

	func rank(context: KismetContext) -> [RankedOpportunity] {
		guard !context.focus.blocksSocial else { return [] }

		let raw = context.suggestionFriends.map { RawOpportunity(friend: $0) }
		var scored: [RankedOpportunity] = []

		for opportunity in raw {
			guard passesHardGates(opportunity, context: context) else { continue }
			let score = signals.reduce(0.0) { partial, signal in
				partial + signal.contribution(opportunity: opportunity, context: context)
			}
			scored.append(
				RankedOpportunity(
					friend: opportunity.friend,
					score: score,
					reasonCodes: reasonCodes(for: opportunity, context: context),
					learnedStats: context.learned.stats(for: opportunity.friend.id)
				)
			)
		}

		return scored
			.sorted { $0.score > $1.score }
			.prefix(topK)
			.map { $0 }
	}

	private func passesHardGates(_ opportunity: RawOpportunity, context: KismetContext) -> Bool {
		let friend = opportunity.friend
		guard friend.presence.isSuggestionEligible else { return false }
		if friend.presence.showsPreciseLocation, friend.distanceMeters > maxDistanceMeters {
			return false
		}
		if context.motion.activity == .automotive {
			return false
		}
		if friend.presence == .friendsOnly, context.user.isBusyNow {
			return false
		}
		return true
	}

	private func reasonCodes(for opportunity: RawOpportunity, context: KismetContext) -> [ExplainCode] {
		var codes: [ExplainCode] = []
		let friend = opportunity.friend

		if friend.presence == .available, !context.user.isBusyNow {
			codes.append(.bothFree)
		} else if let freeFrom = friend.freeFrom, freeFrom > context.generatedAt {
			codes.append(.freeSoon)
		}

		if friend.presence.showsPreciseLocation, friend.distanceMeters < 800 {
			codes.append(.nearbyWalk)
		} else if friend.presence == .approximate {
			codes.append(.approximateNearby)
		}

		if !friend.sharedInterests.isEmpty {
			codes.append(.sharedInterest)
		}

		let hour = Calendar.current.component(.hour, from: context.generatedAt)
		if friend.sharedInterests.contains(where: { $0.localizedCaseInsensitiveContains("coffee") }),
		   (8...11).contains(hour) || (14...17).contains(hour) {
			codes.append(.goodTimeForCoffee)
		}

		if let stats = context.learned.stats(for: friend.id) {
			if stats.completedCount > 0, !stats.isOnCooldown {
				codes.append(.pastHangouts)
			}
			if stats.isOnCooldown {
				codes.append(.metRecently)
			}
		}

		if context.learned.preferredHours.contains(hour) {
			codes.append(.usualMeetupTime)
		}

		return codes
	}
}
