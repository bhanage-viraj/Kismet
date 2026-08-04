import AppIntents
import Foundation

struct WhosFreeNearbyIntent: AppIntent {
	static var title: LocalizedStringResource = "Who's Free Nearby"
	static var description = IntentDescription("Lists friends who are nearby and free to reconnect.")
	static var openAppWhenRun = false

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let cards = await MainActor.run {
			AppEnvironment.shared.suggestionEngine.store.cards
				.filter { $0.presence == .available || $0.presence == .approximate }
		}

		guard !cards.isEmpty else {
			return .result(dialog: "Nobody free nearby right now.")
		}

		let lines = cards.prefix(3).map { card in
			var line = "\(card.displayName) — \(card.formattedDistance)"
			if let venue = card.venueName {
				line += ", near \(venue)"
			}
			return line
		}
		let dialog = lines.joined(separator: ". ")
		return .result(dialog: "\(dialog).")
	}
}

struct WhosNearbyIntent: AppIntent {
	static var title: LocalizedStringResource = "Who's Nearby"
	static var description = IntentDescription("Lists nearby friends surfaced by Kismet Intelligence.")

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let cards = await MainActor.run {
			AppEnvironment.shared.suggestionEngine.store.cards
				.filter(\.presence.isSuggestionEligible)
		}
		guard !cards.isEmpty else {
			return .result(dialog: "No friends nearby right now.")
		}
		let names = cards.prefix(3).map(\.displayName).joined(separator: ", ")
		return .result(dialog: "Nearby: \(names).")
	}
}

struct StartPulseIntent: AppIntent {
	static var title: LocalizedStringResource = "Start a Pulse"
	static var description = IntentDescription("Sends a lightweight Pulse to a nearby friend.")
	static var openAppWhenRun = true

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
			return .result(dialog: "I couldn't find a friend to Pulse.")
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
					venueName: card.venueName,
					source: .pulse,
					outcome: .pending
				)
				env.pendingPulseDraft = nil
			}
			return .result(dialog: "Pulse sent to \(card.displayName).")
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that Pulse."
			return .result(dialog: IntentDialog(stringLiteral: message))
		}
	}
}
