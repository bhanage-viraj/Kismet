import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class SuggestionEngine {
	private(set) var isRunning = false

	let store: SuggestionStore
	private let gateway: FoundationModelsGateway
	private let ranker: OpportunityRanker
	private let venueResolver: VenueResolver
	private var refreshGeneration = 0

	init(
		store: SuggestionStore? = nil,
		gateway: FoundationModelsGateway? = nil,
		ranker: OpportunityRanker = OpportunityRanker(),
		venueResolver: VenueResolver = VenueResolver()
	) {
		self.store = store ?? SuggestionStore()
		self.gateway = gateway ?? FoundationModelsGateway()
		self.ranker = ranker
		self.venueResolver = venueResolver
	}

	func refresh(
		userId: String?,
		displayName: String,
		interests: [String],
		coordinate: CLLocationCoordinate2D,
		placeName: String?,
		people: [MapPerson],
		learned: LearnedSlice = .empty
	) async {
		refreshGeneration += 1
		let generation = refreshGeneration

		isRunning = true
		store.setRefreshing(true)
		defer {
			if generation == refreshGeneration {
				isRunning = false
				store.setRefreshing(false)
			}
		}

		let context = await ContextBuilder(
			userId: userId,
			displayName: displayName,
			interests: interests,
			coordinate: coordinate,
			placeName: placeName,
			people: people,
			learned: learned
		).build()

		guard generation == refreshGeneration else { return }

		let ranked = ranker.rank(context: context)
		guard !ranked.isEmpty else {
			store.replace(
				cards: [],
				usedModel: false,
				status: "No nearby opportunities right now.",
				userCoordinate: coordinate
			)
			return
		}

		let venueStates = await VenueGrounding.resolveStates(
			for: ranked,
			origin: coordinate,
			resolver: venueResolver
		)

		guard generation == refreshGeneration else { return }

		if gateway.isAvailable {
			do {
				let bundle = try await gateway.generateSuggestions(
					context: context,
					ranked: ranked,
					venueStates: venueStates
				)
				guard generation == refreshGeneration else { return }
				let cards = merge(bundle: bundle, ranked: ranked, venueStates: venueStates, context: context)
				if cards.isEmpty {
					store.replace(
						cards: FallbackComposer.cards(from: ranked, venueStates: venueStates, context: context),
						usedModel: false,
						status: gateway.availabilityMessage(),
						userCoordinate: coordinate
					)
				} else {
					store.replace(cards: cards, usedModel: true, status: nil, userCoordinate: coordinate)
					stashPulseDraft(from: cards)
				}
				return
			} catch is CancellationError {
				// Task cancelled by a newer refresh — keep quiet; never surface Swift error text.
				guard generation == refreshGeneration else { return }
				store.replace(
					cards: FallbackComposer.cards(from: ranked, venueStates: venueStates, context: context),
					usedModel: false,
					status: nil,
					userCoordinate: coordinate
				)
				return
			} catch {
				guard generation == refreshGeneration else { return }
				store.replace(
					cards: FallbackComposer.cards(from: ranked, venueStates: venueStates, context: context),
					usedModel: false,
					status: Self.userFacingStatus(for: error),
					userCoordinate: coordinate
				)
				return
			}
		}

		store.replace(
			cards: FallbackComposer.cards(from: ranked, venueStates: venueStates, context: context),
			usedModel: false,
			status: gateway.availabilityMessage(),
			userCoordinate: coordinate
		)
	}

	private func stashPulseDraft(from cards: [SuggestionCard]) {
		guard let card = cards.first else { return }
		let message = card.pulseMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let message, !message.isEmpty else { return }
		AppEnvironment.shared.pendingPulseDraft = PulseDraft(
			friendID: card.friendID,
			displayName: card.displayName,
			venueName: card.venueName,
			message: message,
			suggestionCardID: card.id
		)
	}

	private func merge(
		bundle: PulseSuggestionBundle,
		ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState],
		context: KismetContext
	) -> [SuggestionCard] {
		let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.friend.id, $0) })
		return bundle.suggestions.compactMap { suggestion in
			guard let rankedItem = byID[suggestion.friendID] else { return nil }
			let friend = rankedItem.friend
			guard friend.presence.isSuggestionEligible else { return nil }

			let venue = VenueGrounding.mergeVenue(
				resolverState: venueStates[friend.id],
				modelVenueName: suggestion.venueName,
				modelVenueETAMinutes: suggestion.venueETAMinutes
			)

			var chips = FallbackComposer.factChips(for: rankedItem, venue: venue)
			var reason = suggestion.reason.trimmingCharacters(in: .whitespacesAndNewlines)
			if reason.isEmpty {
				reason = chips.joined(separator: " · ")
			}

			let urgency: SuggestionUrgency = {
				switch suggestion.urgency {
				case .now: .now
				case .soon: .soon
				case .later: .later
				}
			}()

			let ctaTitle: String = {
				let trimmed = suggestion.ctaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
				if !trimmed.isEmpty { return trimmed }
				switch suggestion.action {
				case .sendPulse, .suggestVenue: return "Send a Pulse"
				case .pingWhenFree: return "Ping when free"
				case .none: return "View"
				}
			}()

			let hints = PulseDraftHints.make(item: rankedItem, context: context)
			let activities = VenueGrounding.activityCandidates(for: rankedItem)

			return SuggestionCard(
				id: suggestion.friendID,
				friendID: suggestion.friendID,
				displayName: friend.displayName,
				coordinate: friend.coordinate,
				availability: friend.presence.mapAvailability,
				presence: friend.presence,
				distanceMeters: friend.distanceMeters,
				reason: reason,
				reasonCodes: rankedItem.reasonCodes,
				factChips: chips,
				ctaTitle: ctaTitle,
				ctaSystemImage: suggestion.action == .pingWhenFree ? "hourglass" : "wave.3.right",
				venueName: venue.venueName,
				venueETAMinutes: venue.venueETAMinutes,
				confidence: suggestion.confidence,
				urgency: urgency,
				isModelGenerated: true,
				pulseMessage: PulseMessageComposer.draft(
					venue: venue.selectedVenue,
					hints: hints
				),
				venueCandidates: {
					if case .resolved(let c) = venue.resolution { return c }
					return nil
				}(),
				selectedVenue: venue.selectedVenue,
				venueResolution: venue.resolution,
				venueCoordinate: venue.venueCoordinate,
				venueDisplayETALabel: venue.displayETALabel,
				draftHints: hints,
				activityCandidates: activities
			)
		}
	}

	/// Never surface raw Foundation / cancellation error strings in the UI.
	private static func userFacingStatus(for error: Error) -> String? {
		if error is CancellationError { return nil }
		let ns = error as NSError
		if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return nil }
		if let localized = (error as? LocalizedError)?.errorDescription?
			.trimmingCharacters(in: .whitespacesAndNewlines),
		   !localized.isEmpty,
		   !isRawSystemError(localized) {
			return localized
		}
		return nil
	}

	private static func isRawSystemError(_ message: String) -> Bool {
		let lower = message.lowercased()
		return lower.contains("cancellationerror")
			|| lower.contains("couldn't be completed")
			|| lower.contains("could not be completed")
			|| lower.contains("(swift.")
	}
}
