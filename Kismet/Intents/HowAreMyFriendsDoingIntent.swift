import AppIntents
import Foundation

/// Answers “How are my friends doing?” from on-device Who's Out presence.
/// `nonisolated` avoids MainActor isolation issues when Siri invokes the intent cold.
nonisolated struct HowAreMyFriendsDoingIntent: AppIntent {
	static var title: LocalizedStringResource = "How Are My Friends Doing"
	static var description = IntentDescription(
		"Summarizes your friends’ availability and nearby status from Who's Out."
	)
	/// Bring the app up so stores / App Group are available and Siri can show the dialog.
	static var openAppWhenRun = true

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let dialog = await FriendStatusNarrator.spokenSummarySafe()
		// String dialog is the most reliable Siri surface for App Shortcuts.
		return .result(dialog: "\(dialog)")
	}
}

struct OpenFriendIntent: OpenIntent {
	static var title: LocalizedStringResource = "Open Friend"

	@Parameter(title: "Friend")
	var target: FriendEntity

	@MainActor
	func perform() async throws -> some IntentResult {
		AppEnvironment.shared.mapFriendsStore.select(target.id)
		return .result()
	}
}

enum FriendStatusNarrator {
	/// Never throws / never returns empty — Siri shows a blank card if dialog is missing.
	static func spokenSummarySafe() async -> String {
		if let fromDisk = dialogFromAppGroup() {
			return fromDisk
		}

		do {
			return try await withThrowingTaskGroup(of: String.self) { group in
				group.addTask { @MainActor in
					spokenSummary()
				}
				group.addTask {
					try await Task.sleep(for: .seconds(4))
					throw CancellationError()
				}
				guard let first = try await group.next() else {
					return "Open Who's Out, wait for the map to load, then ask again."
				}
				group.cancelAll()
				return first
			}
		} catch {
			return "I couldn't read friend status just now. Open Who's Out to refresh, then ask again."
		}
	}

	/// Widget / map snapshot — works even when the app process just woke for Siri.
	static func dialogFromAppGroup() -> String? {
		guard let snapshot = AppGroup.loadSnapshot() else { return nil }
		let cards = snapshot.cards
		guard !cards.isEmpty else {
			return snapshot.headline.isEmpty ? nil : snapshot.headline + "."
		}

		let lines = cards.prefix(5).map { card -> String in
			var line = "\(card.displayName) is \(card.statusLabel)"
			if !card.distanceText.isEmpty {
				line += ", \(card.distanceText)"
			}
			if let venue = card.venueName, !venue.isEmpty {
				line += ", near \(venue)"
			}
			return line
		}
		if cards.count > 5 {
			return lines.joined(separator: ". ") + ". And \(cards.count - 5) more in Who's Out."
		}
		return lines.joined(separator: ". ") + "."
	}

	@MainActor
	static func spokenSummary() -> String {
		if let fromDisk = dialogFromAppGroup() {
			return fromDisk
		}

		let env = AppEnvironment.shared
		let entities = FriendEntityQuery.siriVisibleFriends()

		if entities.isEmpty {
			let paired = env.friendsStore.friends
			if paired.isEmpty {
				return "You don't have any friends paired in Who's Out yet."
			}
			let names = paired.prefix(4).map { $0.displayName ?? "a friend" }.joined(separator: ", ")
			return "You've paired with \(names), but I don't have recent presence yet. Open Who's Out to refresh the map, then ask again."
		}

		let lines = entities.prefix(5).map(\.statusSummary)
		if entities.count > 5 {
			return lines.joined(separator: ". ") + ". And \(entities.count - 5) more in Who's Out."
		}
		return lines.joined(separator: ". ") + "."
	}
}
