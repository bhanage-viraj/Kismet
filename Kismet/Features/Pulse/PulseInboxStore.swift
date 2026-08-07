import Foundation
import Observation
import WidgetKit

@Observable
@MainActor
final class PulseInboxStore {
	private(set) var pulses: [IncomingPulse] = []
	private(set) var isLoading = false
	private(set) var lastErrorMessage: String?
	private(set) var lastRefreshedAt: Date?

	/// When true, newly decoded pulses also post a system notification.
	var postsNotificationsForNewPulses = false

	private let client: APIClient
	private let crypto: CryptoBox
	private var notifiedBlobIDs: Set<String> = []

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
			let names = Dictionary(
				uniqueKeysWithValues: friends.map { ($0.userId, $0.displayName ?? "Friend") }
			)
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

			let previousIDs = Set(pulses.map(\.blobId))
			pulses = decoded
			lastRefreshedAt = Date()
			Self.persistOpenPulse(decoded.first)

			if postsNotificationsForNewPulses {
				for pulse in decoded where !previousIDs.contains(pulse.blobId) {
					notifyIfNeeded(pulse)
				}
			}
			notifiedBlobIDs.formIntersection(Set(decoded.map(\.blobId)))
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
			notifiedBlobIDs.remove(pulse.blobId)
			PulseInviteNotifier.clearPulse(blobId: pulse.blobId)
			Self.persistOpenPulse(activePulses.first)
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func reset() {
		pulses = []
		lastErrorMessage = nil
		lastRefreshedAt = nil
		isLoading = false
		notifiedBlobIDs.removeAll()
		Self.persistOpenPulse(nil)
	}

	private func notifyIfNeeded(_ pulse: IncomingPulse) {
		guard notifiedBlobIDs.insert(pulse.blobId).inserted else { return }
		PulseInviteNotifier.notifyNewPulse(
			blobId: pulse.blobId,
			senderDisplayName: pulse.senderDisplayName,
			label: pulse.payload.label,
			emoji: pulse.payload.emoji
		)
	}

	private static func persistOpenPulse(_ pulse: IncomingPulse?) {
		guard let pulse else {
			AppGroup.saveOpenPulse(nil)
			WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
			WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.meetupWidgetKind)
			return
		}
		AppGroup.saveOpenPulse(
			AppGroup.OpenPulse(
				blobId: pulse.blobId,
				senderUserId: pulse.senderUserId,
				senderDisplayName: pulse.senderDisplayName,
				emoji: pulse.payload.emoji,
				label: pulse.payload.label,
				venueName: pulse.payload.venueName,
				expiresAt: pulse.payload.expiresAt,
				pulseId: pulse.payload.pulseId
			)
		)
		WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
		WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.meetupWidgetKind)
	}
}
