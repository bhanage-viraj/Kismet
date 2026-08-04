import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class LocationSharingService {
	private(set) var isSharingActive = false
	private(set) var isUploading = false
	private(set) var lastUploadAt: Date?
	private(set) var lastAcceptedCount = 0
	private(set) var lastErrorMessage: String?
	private(set) var lastPublishedPresence: PresenceState?

	private let client: APIClient
	private let crypto: CryptoBox
	private let minUploadDistance: CLLocationDistance
	private let minUploadInterval: TimeInterval

	private var lastUploadedLocation: CLLocation?
	private var uploadTask: Task<Void, Never>?

	init(
		client: APIClient = .shared,
		crypto: CryptoBox = .shared,
		minUploadDistance: CLLocationDistance = 15,
		minUploadInterval: TimeInterval = 20
	) {
		self.client = client
		self.crypto = crypto
		self.minUploadDistance = minUploadDistance
		self.minUploadInterval = minUploadInterval
	}

	func start() {
		isSharingActive = true
	}

	func stop() {
		isSharingActive = false
		uploadTask?.cancel()
		uploadTask = nil
	}

	/// Encrypts the current fix for each friend with a public key and uploads a LOCATION batch.
	/// Presence shapes precision (Approximate/Eclipse are quantized) and is sealed as `mode`.
	/// Eclipse still publishes a blob so friends can hide the pin immediately.
	func shareIfNeeded(
		location: CLLocation?,
		senderUserId: String?,
		friends: [FriendSummaryDTO],
		presence: PresenceState,
		force: Bool = false
	) {
		guard isSharingActive || force else { return }
		guard let location, let senderUserId, !senderUserId.isEmpty else { return }

		uploadTask?.cancel()
		uploadTask = Task { [weak self] in
			await self?.upload(
				location: location,
				senderUserId: senderUserId,
				friends: friends,
				presence: presence,
				force: force
			)
		}
	}

	private func upload(
		location: CLLocation,
		senderUserId: String,
		friends: [FriendSummaryDTO],
		presence: PresenceState,
		force: Bool
	) async {
		guard !Task.isCancelled else { return }

		let presenceChanged = lastPublishedPresence != presence
		if !force, !presenceChanged, let lastUploadedLocation {
			let moved = location.distance(from: lastUploadedLocation)
			let elapsed = lastUploadAt.map { Date().timeIntervalSince($0) } ?? .infinity
			if moved < minUploadDistance, elapsed < minUploadInterval {
				return
			}
		}

		let recipients = friends.filter { friend in
			guard let key = friend.publicKey, !key.isEmpty else { return false }
			return friend.keyVersion >= 1
		}
		guard !recipients.isEmpty else { return }

		isUploading = true
		lastErrorMessage = nil
		defer { isUploading = false }

		let payload = PresenceLocationPolicy.payload(from: location, presence: presence)

		var blobs: [CreateBlobRequestDTO] = []
		blobs.reserveCapacity(recipients.count)

		for friend in recipients {
			guard let publicKey = friend.publicKey else { continue }
			do {
				let ciphertext = try await crypto.sealLocation(
					payload,
					senderUserId: senderUserId,
					recipientUserId: friend.userId,
					recipientPublicKeyBase64: publicKey,
					recipientKeyVersion: friend.keyVersion
				)
				blobs.append(
					CreateBlobRequestDTO(
						recipientUserId: friend.userId,
						kind: "LOCATION",
						ciphertext: ciphertext,
						keyVersion: friend.keyVersion
					)
				)
			} catch {
				// Skip undecryptable recipients; continue the batch for the rest.
				continue
			}
		}

		guard !blobs.isEmpty, !Task.isCancelled else { return }

		do {
			let response: BlobUploadResponseDTO = try await client.post(
				"/blobs",
				body: BlobUploadRequestDTO(blobs: blobs)
			)
			lastUploadedLocation = location
			lastUploadAt = Date()
			lastAcceptedCount = response.accepted
			lastPublishedPresence = presence
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}
}
