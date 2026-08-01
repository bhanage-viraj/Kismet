import Foundation

/// Boosts friends with successful past hangouts (recency-weighted affinity).
struct FriendAffinitySignal: RankingSignal {
	let id = "friendAffinity"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		guard let stats = context.learned.stats(for: opportunity.friend.id) else { return 0 }
		// Cap so history can't dominate live availability/distance.
		return min(1.2, stats.affinityScore * 0.85)
	}
}

/// Soft-penalizes suggesting someone you just met.
struct RecentMeetupCooldownSignal: RankingSignal {
	let id = "recentMeetupCooldown"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		guard let stats = context.learned.stats(for: opportunity.friend.id),
		      let hours = stats.hoursSinceLastCompletedMeetup else {
			return 0
		}
		if hours < 6 { return -1.2 }
		if hours < 18 { return -0.65 }
		if hours < 36 { return -0.25 }
		return 0
	}
}

/// Boosts when the current hour matches historically preferred meetup hours.
struct PreferredSlotSignal: RankingSignal {
	let id = "preferredSlot"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		let hour = Calendar.current.component(.hour, from: context.generatedAt)
		let preferred = context.learned.preferredHours
		guard !preferred.isEmpty else { return 0 }

		if preferred.contains(hour) { return 0.55 }
		// Nearby hour still counts a little.
		if preferred.contains(where: { abs($0 - hour) == 1 }) { return 0.25 }

		// Per-friend category + coffee interest synergy at preferred hours is handled elsewhere.
		_ = opportunity
		return 0
	}
}

/// Lowers rank when the user repeatedly dismisses suggestions for this friend.
struct DismissPenaltySignal: RankingSignal {
	let id = "dismissPenalty"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		guard let stats = context.learned.stats(for: opportunity.friend.id) else { return 0 }
		if stats.downCount >= 2 { return -0.7 }
		if stats.dismissCount >= 3 { return -0.55 }
		if stats.dismissCount >= 1, stats.ctaCount == 0 { return -0.25 }
		if stats.upCount > 0 { return 0.2 }
		return 0
	}
}
