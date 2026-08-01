import Foundation

struct RawOpportunity: Sendable, Identifiable {
	var id: String { friend.id }
	var friend: FriendPresence
}

protocol RankingSignal: Sendable {
	var id: String { get }
	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double
}

struct AvailabilitySignal: RankingSignal {
	let id = "availability"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		switch opportunity.friend.presence {
		case .available:
			return context.user.isBusyNow ? 0.4 : 1.0
		case .friendsOnly:
			return 0.35
		case .approximate:
			return 0.45
		case .eclipse:
			return -10
		}
	}
}

struct DistanceSignal: RankingSignal {
	let id = "distance"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		guard opportunity.friend.presence.showsPreciseLocation else { return 0.2 }
		let meters = opportunity.friend.distanceMeters
		if meters < 200 { return 1.0 }
		if meters < 600 { return 0.75 }
		if meters < 1_500 { return 0.45 }
		if meters < 3_000 { return 0.2 }
		return 0.05
	}
}

struct SharedInterestSignal: RankingSignal {
	let id = "sharedInterests"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		let shared = Set(opportunity.friend.sharedInterests.map { $0.lowercased() })
		guard !shared.isEmpty else { return 0 }
		let mine = Set(context.user.interests.map { $0.lowercased() })
		let overlap = shared.intersection(mine)
		if overlap.isEmpty { return 0.15 }
		return min(1.0, 0.35 + Double(overlap.count) * 0.25)
	}
}

struct TimeOfDaySignal: RankingSignal {
	let id = "timeOfDay"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		let hour = Calendar.current.component(.hour, from: context.generatedAt)
		let coffeeHours = (8...11).contains(hour) || (14...17).contains(hour)
		let hasCoffee = opportunity.friend.sharedInterests.contains { $0.localizedCaseInsensitiveContains("coffee") }
		if coffeeHours && hasCoffee { return 0.6 }
		if (11...14).contains(hour) { return 0.35 }
		if (17...21).contains(hour) { return 0.4 }
		return 0.15
	}
}

struct MotionSignal: RankingSignal {
	let id = "motion"

	func contribution(opportunity: RawOpportunity, context: KismetContext) -> Double {
		switch context.motion.activity {
		case .walking:
			return opportunity.friend.distanceMeters < 800 ? 0.5 : 0.15
		case .automotive:
			return -0.4
		case .stationary, .unknown:
			return 0.1
		}
	}
}
