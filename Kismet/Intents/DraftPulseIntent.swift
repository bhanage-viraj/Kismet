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
			let cards = env.suggestionEngine.store.cards.filter(\.presence.isSuggestionEligible)
			if let friend {
				return cards.first { $0.friendID == friend.id }
			}
			return cards.first
		}

		guard let card else {
			return .result(dialog: "I couldn't find a friend to draft a Pulse for. Open Who's Out to refresh suggestions first.")
		}

		let message = await MainActor.run { () -> String in
			if let existing = card.pulseMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
			   !existing.isEmpty {
				return existing
			}
			if let venue = card.venueName, !venue.isEmpty {
				return "Free for \(venue)?"
			}
			return "Free to hang soon?"
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
		dialog += ": \"\(message)\". Say Confirm Pulse in Who's Out to send it."
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
		let draft = await MainActor.run { env.pendingPulseDraft }

		guard let draft else {
			return .result(dialog: "No Pulse draft waiting. Try Draft a Pulse first.")
		}

		let card: SuggestionCard? = await MainActor.run {
			let cards = env.suggestionEngine.store.cards.filter(\.presence.isSuggestionEligible)
			if let match = cards.first(where: { $0.friendID == draft.friendID }) {
				return match
			}
			// Reconstruct a minimal eligible card from the draft when store was cleared.
			return nil
		}

		guard let card else {
			await MainActor.run { env.pendingPulseDraft = nil }
			return .result(dialog: "That friend isn't available for a Pulse right now.")
		}

		guard card.presence.isSuggestionEligible else {
			await MainActor.run { env.pendingPulseDraft = nil }
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
				env.pendingPulseDraft = nil
			}
			return .result(dialog: "Pulse sent to \(draft.displayName).")
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that Pulse."
			return .result(dialog: IntentDialog(stringLiteral: message))
		}
	}
}
