import Foundation

/// Ready-to-send Pulse prepared by the Intelligence Layer or DraftPulseIntent.
struct PulseDraft: Sendable, Hashable, Codable {
	var friendID: String
	var displayName: String
	var venueName: String?
	var message: String
	var suggestionCardID: String?
	var createdAt: Date = Date()
}
