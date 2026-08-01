import Foundation

struct PulsePayloadDTO: Codable, Sendable {
	var pulseId: String
	var emoji: String
	var label: String
	var expiresAt: Date
	var venueName: String?
	var createdAt: Date
}

struct OutgoingPulse: Identifiable, Sendable {
	var id: String
	var recipientUserIds: [String]
	var payload: PulsePayloadDTO
}
