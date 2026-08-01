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

	init(
		store: SuggestionStore? = nil,
		gateway: FoundationModelsGateway? = nil,
		ranker: OpportunityRanker = OpportunityRanker()
	) {
		self.store = store ?? SuggestionStore()
		self.gateway = gateway ?? FoundationModelsGateway()
		self.ranker = ranker
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
		isRunning = true
		store.setRefreshing(true)
		defer {
			isRunning = false
			store.setRefreshing(false)
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

		let ranked = ranker.rank(context: context)
		guard !ranked.isEmpty else {
			store.replace(cards: [], usedModel: false, status: "No nearby opportunities right now.")
			return
		}

		if gateway.isAvailable {
			do {
				let bundle = try await gateway.generateSuggestions(context: context, ranked: ranked)
				let cards = merge(bundle: bundle, ranked: ranked)
				if cards.isEmpty {
					store.replace(
						cards: FallbackComposer.cards(from: ranked),
						usedModel: false,
						status: gateway.availabilityMessage()
					)
				} else {
					store.replace(cards: cards, usedModel: true, status: nil)
				}
				return
			} catch {
				store.replace(
					cards: FallbackComposer.cards(from: ranked),
					usedModel: false,
					status: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
				)
				return
			}
		}

		store.replace(
			cards: FallbackComposer.cards(from: ranked),
			usedModel: false,
			status: gateway.availabilityMessage()
		)
	}

	private func merge(bundle: PulseSuggestionBundle, ranked: [RankedOpportunity]) -> [SuggestionCard] {
		let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.friend.id, $0) })
		return bundle.suggestions.compactMap { suggestion in
			guard let rankedItem = byID[suggestion.friendID] else { return nil }
			let friend = rankedItem.friend
			guard friend.presence.isSuggestionEligible else { return nil }

			let chips = FallbackComposer.factChips(for: rankedItem)
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
				venueName: suggestion.venueName,
				venueETAMinutes: suggestion.venueETAMinutes,
				confidence: suggestion.confidence,
				urgency: urgency,
				isModelGenerated: true
			)
		}
	}
}
