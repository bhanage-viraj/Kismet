import Foundation

enum FallbackComposer {
	static func cards(
		from ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState] = [:],
		context: KismetContext? = nil
	) -> [SuggestionCard] {
		ranked.map { item in
			let friend = item.friend
			let venue = VenueGrounding.mergeVenue(
				resolverState: venueStates[friend.id],
				modelVenueName: nil,
				modelVenueETAMinutes: nil
			)
			let chips = factChips(for: item, venue: venue)
			let reason = chips.joined(separator: " · ")
			let cta: (String, String) = {
				switch friend.presence {
				case .available, .approximate:
					return ("Send a Pulse", "wave.3.right")
				case .friendsOnly:
					return ("Ping when free", "hourglass")
				case .eclipse:
					return ("Hidden", "eye.slash")
				}
			}()

			let hints = context.map { PulseDraftHints.make(item: item, context: $0) }

			return SuggestionCard(
				id: friend.id,
				friendID: friend.id,
				displayName: friend.displayName,
				coordinate: friend.coordinate,
				availability: friend.presence.mapAvailability,
				presence: friend.presence,
				distanceMeters: friend.distanceMeters,
				reason: reason.isEmpty ? "Nearby and worth a hello." : reason,
				reasonCodes: item.reasonCodes,
				factChips: chips,
				ctaTitle: cta.0,
				ctaSystemImage: cta.1,
				venueName: venue.venueName,
				venueETAMinutes: venue.venueETAMinutes,
				confidence: min(1, max(0.35, item.score / 3)),
				urgency: urgency(for: item),
				isModelGenerated: false,
				pulseMessage: PulseMessageComposer.draft(
					venue: venue.selectedVenue,
					hints: hints,
					reasonCodes: item.reasonCodes,
					sharedInterests: friend.sharedInterests
				),
				venueCandidates: {
					if case .resolved(let c) = venue.resolution { return c }
					return nil
				}(),
				selectedVenue: venue.selectedVenue,
				venueResolution: venue.resolution,
				venueCoordinate: venue.venueCoordinate,
				venueDisplayETALabel: venue.displayETALabel,
				draftHints: hints
			)
		}
	}

	static func factChips(
		for item: RankedOpportunity,
		venue: MergedVenueFields? = nil
	) -> [String] {
		var chips: [String] = []
		let friend = item.friend

		if item.reasonCodes.contains(.bothFree) {
			if let until = friend.freeUntil {
				chips.append("Free until \(until.formatted(date: .omitted, time: .shortened))")
			} else {
				chips.append("Free right now")
			}
		} else if item.reasonCodes.contains(.freeSoon), let from = friend.freeFrom {
			chips.append("Free \(from.formatted(.relative(presentation: .named)))")
		}

		if item.reasonCodes.contains(.nearbyWalk), friend.presence.showsPreciseLocation {
			chips.append("\(friend.walkingMinutes) min walk")
		} else if item.reasonCodes.contains(.approximateNearby) {
			chips.append("Nearby")
		}

		if item.reasonCodes.contains(.sharedInterest), let interest = friend.sharedInterests.first {
			chips.append("Both like \(interest)")
		}

		if item.reasonCodes.contains(.goodTimeForCoffee) {
			chips.append("Good time for coffee")
		}

		if item.reasonCodes.contains(.pastHangouts) {
			if let count = item.learnedStats?.completedCount, count > 0 {
				chips.append("Met \(count)× before")
			} else {
				chips.append("You've hung out before")
			}
			if let category = item.learnedStats?.preferredCategories.first, category != .other {
				chips.append("Usually \(category.rawValue)")
			}
		}

		if item.reasonCodes.contains(.usualMeetupTime) {
			chips.append("Usual meetup time")
		}

		if item.reasonCodes.contains(.metRecently) {
			chips.append("Met recently")
		}

		appendVenueChips(to: &chips, venue: venue)

		return chips
	}

	static func appendVenueChips(to chips: inout [String], venue: MergedVenueFields?) {
		guard let venue else { return }
		switch venue.resolution {
		case .resolved(let candidates):
			if !candidates.alternatives.isEmpty {
				chips.append("Nearby options available")
			} else if let name = venue.venueName {
				let label = venue.displayETALabel.map { " · \($0)" } ?? ""
				chips.append("Meet at \(name)\(label)")
			}
		case .loading:
			chips.append("Finding places…")
		case .empty:
			break
		}
	}

	private static func urgency(for item: RankedOpportunity) -> SuggestionUrgency {
		if item.reasonCodes.contains(.bothFree), item.reasonCodes.contains(.nearbyWalk) {
			return .now
		}
		if item.reasonCodes.contains(.freeSoon) { return .soon }
		return .later
	}
}
