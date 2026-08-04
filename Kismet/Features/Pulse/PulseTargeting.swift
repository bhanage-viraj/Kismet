import Foundation

/// Decides whether a suggestion card’s friend may receive a Pulse right now.
enum PulseTargeting {
	/// - Available / Friends Only: always eligible (presence path).
	/// - Approximate: only when the card was pitched on shared interest.
	/// - Eclipse: never.
	static func isEligibleRecipient(for suggestion: SuggestionCard) -> Bool {
		switch suggestion.presence {
		case .available, .friendsOnly:
			return true
		case .approximate:
			return suggestion.reasonCodes.contains(.sharedInterest)
		case .eclipse:
			return false
		}
	}
}
