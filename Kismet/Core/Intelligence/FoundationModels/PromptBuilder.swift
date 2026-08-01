import Foundation

enum PromptBuilder {
	static var instructions: String {
		"""
		You are Kismet's reconnection coach. Suggest brief, actionable moments for friends to meet.
		Never invent friends, venues, distances, or availability.
		Only use friend IDs from the candidate list.
		Prefer short CTAs like "Send a Pulse".
		Respect busy/Focus constraints. No conversational filler.
		When a learned memory summary is present, lightly favor habitual hangout times and people — \
		but never invent meetup history. Soften or skip friends marked met_recently.
		"""
	}

	static func prompt(context: KismetContext, ranked: [RankedOpportunity]) -> String {
		var lines: [String] = []
		lines.append("Time: \(context.generatedAt.formatted(date: .omitted, time: .shortened))")
		lines.append("User: \(context.user.displayName)")
		if let place = context.user.placeName {
			lines.append("Place: \(place)")
		}
		lines.append("User busy now: \(context.user.isBusyNow)")
		lines.append("Motion: \(context.motion.activity.rawValue)")
		if !context.user.interests.isEmpty {
			lines.append("User interests: \(context.user.interests.joined(separator: ", "))")
		}
		if context.learned.hasSignal {
			let summary = context.learned.summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
			if !summary.isEmpty {
				lines.append("Learned memory: \(summary)")
			}
			if !context.learned.preferredHours.isEmpty {
				let hours = context.learned.preferredHours
					.sorted()
					.map { String(format: "%02d:00", $0) }
					.joined(separator: ", ")
				lines.append("Usual meetup hours: \(hours)")
			}
		}
		lines.append("Candidates:")
		for item in ranked {
			let friend = item.friend
			var parts = [
				"id=\(friend.id)",
				"name=\(friend.displayName)",
				"presence=\(friend.presence.rawValue)"
			]
			if friend.presence.showsPreciseLocation {
				parts.append("distance_m=\(Int(friend.distanceMeters.rounded()))")
				parts.append("walk_min=\(friend.walkingMinutes)")
			}
			if let until = friend.freeUntil {
				parts.append("free_until=\(until.formatted(date: .omitted, time: .shortened))")
			}
			if let from = friend.freeFrom {
				parts.append("free_from=\(from.formatted(date: .omitted, time: .shortened))")
			}
			if !friend.sharedInterests.isEmpty {
				parts.append("shared=\(friend.sharedInterests.joined(separator: "|"))")
			}
			if let stats = item.learnedStats {
				parts.append("past_meetups=\(stats.completedCount)")
				if let hours = stats.hoursSinceLastCompletedMeetup {
					parts.append("hours_since_last_meetup=\(Int(hours.rounded()))")
				}
				if stats.isOnCooldown {
					parts.append("met_recently=true")
				}
				if let category = stats.preferredCategories.first, category != .other {
					parts.append("usual_spot=\(category.rawValue)")
				}
			}
			parts.append("codes=\(item.reasonCodes.map(\.rawValue).joined(separator: "|"))")
			lines.append("- " + parts.joined(separator: "; "))
		}
		lines.append("Return up to \(ranked.count) structured suggestions. Pick a venue name only if clearly implied by shared interests or usual_spot; otherwise leave venue empty.")
		return lines.joined(separator: "\n")
	}
}
