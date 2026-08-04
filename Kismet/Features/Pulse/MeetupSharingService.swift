import Foundation

/// Publishes / opens MEETUP blobs so Pulse accept starts a Live Activity on both devices.
@MainActor
final class MeetupSharingService {
	private let client: APIClient
	private let crypto: CryptoBox

	init(client: APIClient = .shared, crypto: CryptoBox = .shared) {
		self.client = client
		self.crypto = crypto
	}

	/// Acceptor → original Pulse sender: sealed meetup details.
	func notifyPeerOfAccept(
		payload: MeetupPayloadDTO,
		senderUserId: String,
		peerUserId: String,
		friends: [FriendSummaryDTO]
	) async {
		guard let friend = friends.first(where: { $0.userId == peerUserId }),
		      let publicKey = friend.publicKey,
		      !publicKey.isEmpty
		else { return }

		do {
			let ciphertext = try await crypto.sealJSON(
				payload,
				kind: "MEETUP",
				senderUserId: senderUserId,
				recipientUserId: peerUserId,
				recipientPublicKeyBase64: publicKey,
				recipientKeyVersion: friend.keyVersion
			)
			let _: BlobUploadResponseDTO = try await client.post(
				"/blobs",
				body: BlobUploadRequestDTO(
					blobs: [
						CreateBlobRequestDTO(
							recipientUserId: peerUserId,
							kind: "MEETUP",
							ciphertext: ciphertext,
							keyVersion: friend.keyVersion
						),
					]
				)
			)
		} catch {
			// Non-fatal — acceptor's local Live Activity still runs.
		}
	}

	/// Opens pending MEETUP blobs and returns payloads (acks as it goes).
	func consumePendingMeetups(friends: [FriendSummaryDTO]) async -> [(senderUserId: String, payload: MeetupPayloadDTO)] {
		guard let myUserId = KeychainStore.get(.userId), !myUserId.isEmpty else { return [] }
		let keys = Dictionary(
			uniqueKeysWithValues: friends.compactMap { friend -> (String, String)? in
				guard let key = friend.publicKey, !key.isEmpty else { return nil }
				return (friend.userId, key)
			}
		)
		var results: [(String, MeetupPayloadDTO)] = []
		var ackIds: [String] = []

		do {
			let pending: PendingBlobsResponseDTO = try await client.get("/blobs/pending")
			for blob in pending.blobs where blob.kind.uppercased() == "MEETUP" {
				guard let senderKey = keys[blob.senderUserId] else { continue }
				do {
					let payload: MeetupPayloadDTO = try await crypto.openJSON(
						MeetupPayloadDTO.self,
						ciphertextBase64: blob.ciphertext,
						kind: "MEETUP",
						senderUserId: blob.senderUserId,
						recipientUserId: myUserId,
						senderPublicKeyBase64: senderKey,
						recipientKeyVersion: blob.keyVersion
					)
					results.append((blob.senderUserId, payload))
					ackIds.append(blob.id)
				} catch {
					continue
				}
			}
			if !ackIds.isEmpty {
				let _: BlobAckResponseDTO = try await client.post(
					"/blobs/ack",
					body: BlobAckRequestDTO(blobIds: ackIds)
				)
			}
		} catch {
			return results
		}
		return results
	}
}
