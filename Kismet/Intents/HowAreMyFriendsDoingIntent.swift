import AppIntents
import Foundation

/// Answers “How are my friends doing?” from on-device Kismet presence — not a generic Siri guess.
struct HowAreMyFriendsDoingIntent: AppIntent {
	static var title: LocalizedStringResource = "How Are My Friends Doing"
	static var description = IntentDescription(
		"Summarizes your friends’ availability and nearby status from Kismet."
	)
	static var openAppWhenRun = false

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let dialog = await MainActor.run { FriendStatusNarrator.spokenSummary() }
		return .result(dialog: IntentDialog(stringLiteral: dialog))
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

@MainActor
enum FriendStatusNarrator {
	static func spokenSummary() -> String {
		let env = AppEnvironment.shared
		let entities = FriendEntityQuery.siriVisibleFriends()

		if entities.isEmpty {
			let paired = env.friendsStore.friends
			if paired.isEmpty {
				return "You don’t have any friends paired in Kismet yet."
			}
			let names = paired.prefix(4).map { $0.displayName ?? "a friend" }.joined(separator: ", ")
			return "You’ve paired with \(names), but I don’t have recent presence yet. Open Kismet to refresh."
		}

		let lines = entities.prefix(5).map(\.statusSummary)
		if entities.count > 5 {
			return lines.joined(separator: ". ") + ". And \(entities.count - 5) more in Kismet."
		}
		return lines.joined(separator: ". ") + "."
	}
}
