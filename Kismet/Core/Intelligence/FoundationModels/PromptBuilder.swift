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
		If grounded_venue is present for a candidate, treat it as a known nearby place fact — \
		do not invent other venue names. Leave venueName and pulseMessage empty in structured output \
		(the app attaches grounded venues and drafts the Pulse body from the selected place).
		"""
	}

	static func prompt(
		context: KismetContext,
		ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState] = [:]
	) -> String {
		var lines: [String] = []
		lines.append("Time: \(context.generatedAt.formatted(date: .omitted, time: .shortened))")
		lines.append("User: \(context.user.displayName)")
		if let place = context.user.placeName {
			lines.append("Place: \(place)")
		}
		lines.append("User busy now: \(context.user.isBusyNow)")
		lines.append("Motion: \(context.motion.activity.rawValue)")
		if context.weather.condition != .unknown {
			let weatherLine = context.weather.summary.map { "Weather: \($0)" }
				?? "Weather: \(context.weather.condition.rawValue)"
			lines.append(weatherLine)
		}
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
			if case .resolved(let candidates) = venueStates[friend.id] {
				let suggested = candidates.suggested
				parts.append("grounded_venue=\(suggested.name)")
				if let label = suggested.displayETALabel {
					parts.append("grounded_distance=\(label)")
				}
				if !candidates.alternatives.isEmpty {
					parts.append("venue_alternatives=\(candidates.alternatives.count)")
				}
			}
			parts.append("codes=\(item.reasonCodes.map(\.rawValue).joined(separator: "|"))")
			lines.append("- " + parts.joined(separator: "; "))
		}
		lines.append(
			"""
			Return up to \(ranked.count) structured suggestions. \
			Leave venueName, venueETAMinutes, and pulseMessage empty — the app supplies grounded venues and the Pulse draft.
			"""
		)
		return lines.joined(separator: "\n")
	}
}
