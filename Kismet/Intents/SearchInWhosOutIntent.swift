import AppIntents
import Foundation

/// Handles Siri/Apple Intelligence “search within Who's Out” requests.
/// Without this, Siri replies: “I can't search within the … app …”.
///
/// Important: typed Ask Siri queries like “Pulse them” often land here via the
/// system search schema — they must actually Pulse, not dump distances.
@available(iOS 18.0, *)
@AssistantIntent(schema: .system.search)
struct SearchInWhosOutIntent: ShowInAppSearchResultsIntent {
	static let searchScopes: [StringSearchScope] = [.general]
	static let openAppWhenRun = true

	var criteria: StringSearchCriteria

	func perform() async throws -> some IntentResult & ProvidesDialog {
		let term = criteria.term

		if PulseSiriActions.isPulseQuery(term) {
			let dialog = try await PulseSiriActions.performPulse(
				plural: PulseSiriActions.isPluralPulseQuery(term)
			)
			return .result(dialog: dialog)
		}

		let dialog = await FriendStatusNarrator.spokenSummarySafe()
		return .result(dialog: IntentDialog(stringLiteral: dialog))
	}
}
