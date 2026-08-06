import AppIntents
import Foundation

struct DraftPulseIntent: AppIntent {
	static var title: LocalizedStringResource = "Draft a Pulse"
	static var description = IntentDescription(
		"Prepares a Pulse to a nearby friend without sending it. Use Confirm Pulse to send."
	)
	static var openAppWhenRun = false

	@Parameter(title: "Friend")
	var friend: FriendEntity?

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let env = AppEnvironment.shared
		let card: SuggestionCard? = await MainActor.run {
			env.suggestionEngine.store.rehydrateFromAppGroupIfNeeded()
			let cards = env.suggestionEngine.store.cards.filter(\.presence.isSuggestionEligible)
			if let friend {
				return cards.first { $0.friendID == friend.id }
			}
			return cards.first
		}

		guard let card else {
			return .result(dialog: "I couldn't find a friend to draft a Pulse for. Open Kismet to refresh suggestions first.")
		}

		let message = await MainActor.run { () -> String in
			PulseMessageComposer.draft(
				venue: card.selectedVenue ?? card.venueCandidates?.suggested,
				hints: card.draftHints,
				reasonCodes: card.reasonCodes,
				sharedInterests: card.draftHints?.sharedInterests ?? []
			)
		}

		await MainActor.run {
			env.pendingPulseDraft = PulseDraft(
				friendID: card.friendID,
				displayName: card.displayName,
				venueName: card.venueName,
				message: message,
				suggestionCardID: card.id
			)
		}

		var dialog = "Draft ready for \(card.displayName)"
		if let venue = card.venueName {
			dialog += " near \(venue)"
		}
		dialog += ": \"\(message)\". Say Confirm Pulse in Kismet to send it."
		return .result(dialog: IntentDialog(stringLiteral: dialog))
	}
}

struct ConfirmPulseIntent: AppIntent {
	static var title: LocalizedStringResource = "Confirm Pulse"
	static var description = IntentDescription(
		"Sends the Pulse draft prepared by Draft a Pulse."
	)
	static var openAppWhenRun = false

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let env = AppEnvironment.shared

		let draft = await MainActor.run { env.resolvedPendingPulseDraft() }
		guard let draft else {
			return .result(dialog: "No Pulse draft waiting. Try Draft a Pulse first.")
		}

		let card: SuggestionCard? = await MainActor.run {
			env.suggestionEngine.store.rehydrateFromAppGroupIfNeeded()
			let cards = env.suggestionEngine.store.cards.filter(\.presence.isSuggestionEligible)
			if let match = cards.first(where: { $0.friendID == draft.friendID }) {
				var hydrated = match
				if hydrated.pulseMessage?.isEmpty != false {
					hydrated.pulseMessage = draft.message
				}
				if hydrated.venueName == nil {
					hydrated.venueName = draft.venueName
				}
				return hydrated
			}

			// Reconstruct from draft (+ snapshot card when available) after cold start.
			let snapshotCard = AppGroup.loadSnapshot()?.cards.first {
				$0.friendID == draft.friendID || $0.id == draft.suggestionCardID
			}
			return SuggestionCard.fromPulseDraft(draft, snapshotCard: snapshotCard)
		}

		guard let card else {
			await MainActor.run { env.clearPendingPulseDraft() }
			return .result(dialog: "That friend isn't available for a Pulse right now.")
		}

		guard card.presence.isSuggestionEligible else {
			await MainActor.run { env.clearPendingPulseDraft() }
			return .result(dialog: "That friend is hidden or unavailable.")
		}

		do {
			_ = try await env.pulsePublisher.send(
				from: card,
				senderUserId: KeychainStore.get(.userId),
				friends: await MainActor.run { env.friendsStore.friends }
			)
			await MainActor.run {
				env.meetupMemoryStore.recordFeedback(
					friendUserId: card.friendID,
					action: .cta,
					reasonCodes: card.reasonCodes.map(\.rawValue)
				)
				env.meetupMemoryStore.recordMeetup(
					friendUserId: card.friendID,
					friendDisplayName: card.displayName,
					venueName: draft.venueName ?? card.venueName,
					source: .pulse,
					outcome: .pending
				)
				env.clearPendingPulseDraft()
			}
			return .result(dialog: "Pulse sent to \(draft.displayName).")
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that Pulse."
			return .result(dialog: IntentDialog(stringLiteral: message))
		}
	}
}
