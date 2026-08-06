import Foundation
import Observation

enum PulsePublisherError: LocalizedError {
	case missingUser
	case noRecipients
	case recipientUnavailable
	case uploadFailed(String)

	var errorDescription: String? {
		switch self {
		case .missingUser: "Sign in to send a Pulse."
		case .noRecipients: "No eligible friends to receive this Pulse."
		case .recipientUnavailable: "That friend isn’t available for a Pulse right now."
		case .uploadFailed(let message): message
		}
	}
}

@Observable
@MainActor
final class PulsePublisher {
	private(set) var lastSentPulse: OutgoingPulse?
	private(set) var isSending = false
	private(set) var lastErrorMessage: String?

	private let client: APIClient
	private let crypto: CryptoBox

	init(client: APIClient = .shared, crypto: CryptoBox = .shared) {
		self.client = client
		self.crypto = crypto
	}

	func send(
		from suggestion: SuggestionCard,
		senderUserId: String?,
		friends: [FriendSummaryDTO]
	) async throws -> OutgoingPulse {
		guard let senderUserId, !senderUserId.isEmpty else {
			throw PulsePublisherError.missingUser
		}

		isSending = true
		lastErrorMessage = nil
		defer { isSending = false }

		guard PulseTargeting.isEligibleRecipient(for: suggestion) else {
			throw PulsePublisherError.recipientUnavailable
		}

		let expiresAt = Date().addingTimeInterval(45 * 60)
		// Venue lat/lon are the MapKit place pin from VenueResolver / selectedVenue — never live GPS.
		let venue = PulseVenueFields.fromSuggestion(suggestion)
		let draftMessage: String? = {
			if let message = suggestion.pulseMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
			   !message.isEmpty {
				return message
			}
			if let draft = AppEnvironment.shared.pendingPulseDraft,
			   draft.friendID == suggestion.friendID {
				let trimmed = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
				return trimmed.isEmpty ? nil : trimmed
			}
			return nil
		}()

		let payload = PulsePayloadDTO(
			pulseId: UUID().uuidString,
			emoji: "👋",
			label: suggestion.ctaTitle,
			expiresAt: expiresAt,
			venueName: venue.name,
			venueLatitude: venue.latitude,
			venueLongitude: venue.longitude,
			message: draftMessage,
			createdAt: Date()
		)

		// Target the suggested friend if they have a public key; otherwise no-op.
		let recipients = friends.filter { friend in
			friend.userId == suggestion.friendID
				&& friend.publicKey?.isEmpty == false
		}
		guard !recipients.isEmpty else {
			throw PulsePublisherError.noRecipients
		}

		var blobs: [CreateBlobRequestDTO] = []
		for friend in recipients {
			guard let publicKey = friend.publicKey else { continue }
			do {
				let ciphertext = try await crypto.sealJSON(
					payload,
					kind: "PULSE",
					senderUserId: senderUserId,
					recipientUserId: friend.userId,
					recipientPublicKeyBase64: publicKey,
					recipientKeyVersion: friend.keyVersion
				)
				blobs.append(
					CreateBlobRequestDTO(
						recipientUserId: friend.userId,
						kind: "PULSE",
						ciphertext: ciphertext,
						keyVersion: friend.keyVersion
					)
				)
			} catch {
				continue
			}
		}

		guard !blobs.isEmpty else {
			throw PulsePublisherError.noRecipients
		}

		do {
			let _: BlobUploadResponseDTO = try await client.post(
				"/blobs",
				body: BlobUploadRequestDTO(blobs: blobs)
			)
		} catch {
			let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			lastErrorMessage = message
			throw PulsePublisherError.uploadFailed(message)
		}

		let outgoing = OutgoingPulse(
			id: payload.pulseId,
			recipientUserIds: blobs.map(\.recipientUserId),
			payload: payload
		)
		lastSentPulse = outgoing
		return outgoing
	}
}
