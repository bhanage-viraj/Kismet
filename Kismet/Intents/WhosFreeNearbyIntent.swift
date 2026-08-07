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
	static var description = IntentDescription("Lists nearby friends surfaced by Who's Out Intelligence.")

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
	static var description = IntentDescription("Sends a Pulse to a nearby friend.")
	static var openAppWhenRun = true

	@Parameter(title: "Friend")
	var friend: FriendEntity?

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let dialog = try await PulseSiriActions.performPulse(friend: friend, plural: false)
		return .result(dialog: dialog)
	}
}

/// Plural “Pulse them” — sends to up to a few nearby free friends.
struct PulseThemIntent: AppIntent {
	static var title: LocalizedStringResource = "Pulse Them"
	static var description = IntentDescription(
		"Sends a Pulse to nearby free friends (up to three)."
	)
	static var openAppWhenRun = true

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let dialog = try await PulseSiriActions.performPulse(plural: true)
		return .result(dialog: dialog)
	}
}
