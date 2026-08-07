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
		guard PulseTargeting.isEligibleRecipient(for: suggestion) else {
			throw PulsePublisherError.recipientUnavailable
		}
		return try await send(
			draft: .from(card: suggestion),
			senderUserId: senderUserId,
			friends: friends
		)
	}

	func send(
		draft: PulseComposeDraft,
		senderUserId: String?,
		friends: [FriendSummaryDTO]
	) async throws -> OutgoingPulse {
		guard let senderUserId, !senderUserId.isEmpty else {
			throw PulsePublisherError.missingUser
		}

		isSending = true
		lastErrorMessage = nil
		defer { isSending = false }

		let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let venue = PulseVenueFields.fromDraft(draft)
		let startsAt = draft.startsAt
		let expiresAt = max(startsAt.addingTimeInterval(45 * 60), Date().addingTimeInterval(45 * 60))
		let message: String? = {
			let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { return nil }
			return trimmed
		}()

		let payload = PulsePayloadDTO(
			pulseId: UUID().uuidString,
			emoji: draft.activity.emoji,
			label: title.isEmpty ? draft.activity.defaultTitle : title,
			expiresAt: expiresAt,
			venueName: venue.name,
			venueLatitude: venue.latitude,
			venueLongitude: venue.longitude,
			message: message,
			createdAt: Date(),
			venueAddress: venue.address,
			startsAt: startsAt,
			activityId: draft.activity.rawValue
		)

		let recipients = friends.filter { friend in
			friend.userId == draft.recipientUserId
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
