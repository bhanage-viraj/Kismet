import Foundation

struct LearnedFeatureBuilder: Sendable {
	/// Hours after a completed meetup during which we cool down that friend.
	var cooldownHours: Double = 18
	/// Half-life for affinity decay (days).
	var affinityHalfLifeDays: Double = 21
	var maxSummaryFriends: Int = 3

	func build(
		meetups: [MeetupEventSnapshot],
		feedback: [SuggestionFeedbackSnapshot],
		now: Date = Date(),
		existingSummary: String? = nil
	) -> LearnedSlice {
		let completed = meetups.filter { $0.outcome == .completed }
		let friendIDs = Set(meetups.map(\.friendUserId)).union(feedback.map(\.friendUserId))

		var byFriend: [String: FriendLearnedStats] = [:]
		for friendID in friendIDs {
			let friendMeetups = meetups.filter { $0.friendUserId == friendID }
			let friendCompleted = friendMeetups.filter { $0.outcome == .completed }
			let friendFeedback = feedback.filter { $0.friendUserId == friendID }
			let displayName = friendMeetups.first?.friendDisplayName
				?? friendCompleted.first?.friendDisplayName
				?? "Friend"

			let lastCompleted = friendCompleted.map(\.startedAt).max()
			let hoursSince: Double? = lastCompleted.map { now.timeIntervalSince($0) / 3600 }

			let affinity = affinityScore(for: friendCompleted, now: now)
			let categories = categoryHistogram(friendCompleted)
				.sorted { $0.value > $1.value }
				.map(\.key)

			byFriend[friendID] = FriendLearnedStats(
				friendUserId: friendID,
				friendDisplayName: displayName,
				completedCount: friendCompleted.count,
				affinityScore: affinity,
				hoursSinceLastCompletedMeetup: hoursSince,
				dismissCount: friendFeedback.filter { $0.action == .dismissed }.count,
				ctaCount: friendFeedback.filter { $0.action == .cta }.count,
				upCount: friendFeedback.filter { $0.action == .up }.count,
				downCount: friendFeedback.filter { $0.action == .down }.count,
				preferredCategories: Array(categories.prefix(3))
			)
		}

		let preferredHours = hourHistogram(completed)
			.sorted { $0.value > $1.value }
			.prefix(4)
			.map(\.key)

		let preferredCategories = categoryHistogram(completed)
			.sorted { $0.value > $1.value }
			.prefix(3)
			.map(\.key)

		let topFriendIds = byFriend.values
			.sorted { $0.affinityScore > $1.affinityScore }
			.prefix(maxSummaryFriends)
			.map(\.friendUserId)

		let summary: String
		if let existingSummary, !existingSummary.isEmpty, completed.isEmpty {
			summary = existingSummary
		} else {
			summary = makeSummary(
				byFriend: byFriend,
				topFriendIds: topFriendIds,
				preferredHours: preferredHours,
				preferredCategories: preferredCategories
			)
		}

		return LearnedSlice(
			summaryText: summary,
			preferredHours: preferredHours,
			preferredCategories: preferredCategories,
			topFriendIds: Array(topFriendIds),
			byFriend: byFriend,
			completedMeetupCount: completed.count,
			updatedAt: now
		)
	}

	// MARK: - Scoring

	private func affinityScore(for completed: [MeetupEventSnapshot], now: Date) -> Double {
		guard !completed.isEmpty else { return 0 }
		let halfLifeSeconds = affinityHalfLifeDays * 24 * 3600
		var score = 0.0
		for event in completed {
			let age = max(0, now.timeIntervalSince(event.startedAt))
			let decay = pow(0.5, age / halfLifeSeconds)
			score += decay
		}
		return score
	}

	private func hourHistogram(_ events: [MeetupEventSnapshot]) -> [Int: Int] {
		var counts: [Int: Int] = [:]
		let calendar = Calendar.current
		for event in events {
			let hour = calendar.component(.hour, from: event.startedAt)
			counts[hour, default: 0] += 1
		}
		return counts
	}

	private func categoryHistogram(_ events: [MeetupEventSnapshot]) -> [VenueCategory: Int] {
		var counts: [VenueCategory: Int] = [:]
		for event in events {
			counts[event.venueCategory, default: 0] += 1
		}
		return counts
	}

	private func makeSummary(
		byFriend: [String: FriendLearnedStats],
		topFriendIds: [String],
		preferredHours: [Int],
		preferredCategories: [VenueCategory]
	) -> String {
		guard !topFriendIds.isEmpty || !preferredHours.isEmpty else { return "" }

		var parts: [String] = []

		let friendBits: [String] = topFriendIds.compactMap { id in
			guard let stats = byFriend[id], stats.completedCount > 0 else { return nil }
			var bit = "\(stats.friendDisplayName) (\(stats.completedCount)×)"
			if let category = stats.preferredCategories.first, category != .other {
				bit += " · \(category.rawValue)"
			}
			if stats.isOnCooldown {
				bit += " · met recently"
			}
			return bit
		}
		if !friendBits.isEmpty {
			parts.append("Often meets: " + friendBits.joined(separator: "; "))
		}

		if !preferredHours.isEmpty {
			let hours = preferredHours
				.sorted()
				.map { String(format: "%02d:00", $0) }
				.joined(separator: ", ")
			parts.append("Preferred hours: \(hours)")
		}

		if !preferredCategories.isEmpty {
			let cats = preferredCategories.map(\.rawValue).joined(separator: ", ")
			parts.append("Preferred spots: \(cats)")
		}

		return parts.joined(separator: ". ")
	}
}
