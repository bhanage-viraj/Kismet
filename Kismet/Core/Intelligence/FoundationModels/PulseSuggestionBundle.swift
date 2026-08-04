import Foundation
import FoundationModels

@Generable
struct PulseSuggestionBundle {
	@Guide(description: "0 to 3 ranked reconnection opportunities", .maximumCount(3))
	var suggestions: [PulseSuggestion]
}

@Generable
struct PulseSuggestion {
	@Guide(description: "Friend user id copied exactly from the candidate list")
	var friendID: String

	@Guide(.range(0.0...1.0))
	var confidence: Double

	var action: PulseAction
	var urgency: GenerableUrgency

	@Guide(description: "Short CTA label such as Send a Pulse")
	var ctaTitle: String

	var venueName: String?
	var venueETAMinutes: Int?

	@Guide(description: "One-line reason grounded only in provided facts")
	var reason: String

	@Guide(description: "Optional short Pulse message ready to send; empty if not drafting")
	var pulseMessage: String?
}

@Generable
enum PulseAction {
	case sendPulse
	case pingWhenFree
	case suggestVenue
	case none
}

@Generable
enum GenerableUrgency {
	case now
	case soon
	case later
}
