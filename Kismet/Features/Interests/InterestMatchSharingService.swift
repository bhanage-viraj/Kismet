import Foundation
import Observation

@Observable
@MainActor
final class InterestMatchSharingService {
	private(set) var lastErrorMessage: String?
	private let client: APIClient
	private let crypto: CryptoBox

	init(client: APIClient = .shared, crypto: CryptoBox = .shared) {
		self.client = client
		self.crypto = crypto
	}

	/// Seals the viewer's interest ids to each friend with a public key.
	func share(interestIds: [String], senderUserId: String?, friends: [FriendSummaryDTO]) async {
		guard let senderUserId, !senderUserId.isEmpty else { return }
		let normalized = Array(Set(interestIds.map { $0.lowercased() })).sorted()
		let payload = InterestMatchPayloadDTO(interestIds: normalized, updatedAt: Date())
		lastErrorMessage = nil

		var blobs: [CreateBlobRequestDTO] = []
		for friend in friends {
			guard let publicKey = friend.publicKey, !publicKey.isEmpty else { continue }
			do {
				let ciphertext = try await crypto.sealJSON(
					payload,
					kind: "INTEREST_MATCH",
					senderUserId: senderUserId,
					recipientUserId: friend.userId,
					recipientPublicKeyBase64: publicKey,
					recipientKeyVersion: friend.keyVersion
				)
				blobs.append(
					CreateBlobRequestDTO(
						recipientUserId: friend.userId,
						kind: "INTEREST_MATCH",
						ciphertext: ciphertext,
						keyVersion: friend.keyVersion
					)
				)
			} catch {
				continue
			}
		}
		guard !blobs.isEmpty else { return }

		do {
			let _: BlobUploadResponseDTO = try await client.post(
				"/blobs",
				body: BlobUploadRequestDTO(blobs: blobs)
			)
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	/// Opens pending INTEREST_MATCH blobs → senderUserId → their interest ids.
	func loadFriendInterests(friends: [FriendSummaryDTO]) async -> [String: [String]] {
		guard let myUserId = KeychainStore.get(.userId), !myUserId.isEmpty else { return [:] }
		let keys = Dictionary(
			uniqueKeysWithValues: friends.compactMap { friend -> (String, String)? in
				guard let key = friend.publicKey, !key.isEmpty else { return nil }
				return (friend.userId, key)
			}
		)
		do {
			let pending: PendingBlobsResponseDTO = try await client.get("/blobs/pending")
			var bySender: [String: [String]] = [:]
			for blob in pending.blobs where blob.kind.uppercased() == "INTEREST_MATCH" {
				guard let senderKey = keys[blob.senderUserId] else { continue }
				do {
					let payload: InterestMatchPayloadDTO = try await crypto.openJSON(
						InterestMatchPayloadDTO.self,
						ciphertextBase64: blob.ciphertext,
						kind: "INTEREST_MATCH",
						senderUserId: blob.senderUserId,
						recipientUserId: myUserId,
						senderPublicKeyBase64: senderKey,
						recipientKeyVersion: blob.keyVersion
					)
					bySender[blob.senderUserId] = payload.interestIds
				} catch {
					continue
				}
			}
			return bySender
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return [:]
		}
	}
}
