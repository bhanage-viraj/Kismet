import Foundation

struct PulsePayloadDTO: Codable, Sendable, Equatable {
	var pulseId: String
	var emoji: String
	var label: String
	var expiresAt: Date
	var venueName: String?
	var createdAt: Date
	/// Optional street / neighborhood line under the venue name.
	var venueAddress: String? = nil
	/// Planned meet time. Falls back to `expiresAt` for older payloads.
	var startsAt: Date? = nil
	/// Compose activity id (`coffee`, `walk`, …).
	var activityId: String? = nil

	var plannedAt: Date { startsAt ?? expiresAt }
}

struct OutgoingPulse: Identifiable, Sendable {
	var id: String
	var recipientUserIds: [String]
	var payload: PulsePayloadDTO
}

struct IncomingPulse: Identifiable, Sendable, Equatable {
	var id: String { blobId }
	var blobId: String
	var senderUserId: String
	var senderDisplayName: String
	var payload: PulsePayloadDTO
	var receivedAt: Date

	var isExpired: Bool {
		payload.expiresAt <= Date()
	}
}
