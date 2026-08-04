import Foundation
import Observation

@Observable
@MainActor
final class PulseInboxStore {
	private(set) var pulses: [IncomingPulse] = []
	private(set) var isLoading = false
	private(set) var lastErrorMessage: String?
	private(set) var lastRefreshedAt: Date?

	private let client: APIClient
	private let crypto: CryptoBox

	init(client: APIClient = .shared, crypto: CryptoBox = .shared) {
		self.client = client
		self.crypto = crypto
	}

	var activePulses: [IncomingPulse] {
		pulses.filter { !$0.isExpired }.sorted { $0.payload.expiresAt < $1.payload.expiresAt }
	}

	func refresh(friends: [FriendSummaryDTO]) async {
		isLoading = true
		lastErrorMessage = nil
		defer { isLoading = false }

		guard let myUserId = KeychainStore.get(.userId), !myUserId.isEmpty else {
			pulses = []
			return
		}

		do {
			let pending: PendingBlobsResponseDTO = try await client.get("/blobs/pending")
			let names = Dictionary(uniqueKeysWithValues: friends.map { ($0.userId, $0.displayName) })
			let keys = Dictionary(
				uniqueKeysWithValues: friends.compactMap { friend -> (String, String)? in
					guard let key = friend.publicKey, !key.isEmpty else { return nil }
					return (friend.userId, key)
				}
			)

			var decoded: [IncomingPulse] = []
			for blob in pending.blobs where blob.kind.uppercased() == "PULSE" {
				guard let senderKey = keys[blob.senderUserId] else { continue }
				do {
					let payload: PulsePayloadDTO = try await crypto.openJSON(
						PulsePayloadDTO.self,
						ciphertextBase64: blob.ciphertext,
						kind: "PULSE",
						senderUserId: blob.senderUserId,
						recipientUserId: myUserId,
						senderPublicKeyBase64: senderKey,
						recipientKeyVersion: blob.keyVersion
					)
					guard payload.expiresAt > Date() else { continue }
					decoded.append(
						IncomingPulse(
							blobId: blob.id,
							senderUserId: blob.senderUserId,
							senderDisplayName: names[blob.senderUserId] ?? "Friend",
							payload: payload,
							receivedAt: blob.updatedAt
						)
					)
				} catch {
					continue
				}
			}

			pulses = decoded
			lastRefreshedAt = Date()
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func acknowledge(_ pulse: IncomingPulse) async {
		do {
			let _: BlobAckResponseDTO = try await client.post(
				"/blobs/ack",
				body: BlobAckRequestDTO(blobIds: [pulse.blobId])
			)
			pulses.removeAll { $0.blobId == pulse.blobId }
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func reset() {
		pulses = []
		lastErrorMessage = nil
		lastRefreshedAt = nil
		isLoading = false
	}
}
