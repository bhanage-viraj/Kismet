import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class MapFriendsStore {
	private(set) var friends: [MapPerson] = []
	private(set) var selectedFriendID: String?
	private(set) var isLoading = false
	private(set) var lastErrorMessage: String?
	private(set) var lastRefreshedAt: Date?

	private let client: APIClient
	private let crypto: CryptoBox

	init(client: APIClient = .shared, crypto: CryptoBox = .shared) {
		self.client = client
		self.crypto = crypto
	}

	var selectedFriend: MapPerson? {
		guard let selectedFriendID else { return nil }
		return friends.first { $0.id == selectedFriendID }
	}

	#if DEBUG
	/// Canvas / Preview host only — not used on the live map path.
	func loadPreviewMocks(around coordinate: CLLocationCoordinate2D) {
		friends = MockFriendsProvider.friends(around: coordinate)
	}
	#endif

	func refresh(around coordinate: CLLocationCoordinate2D?) async {
		isLoading = true
		lastErrorMessage = nil
		defer { isLoading = false }

		let origin = coordinate ?? MockFriendsProvider.fallbackCoordinate
		let myUserId = KeychainStore.get(.userId)

		do {
			async let mapResponse: MapFriendsResponseDTO = client.get("/map/friends")
			async let pendingResponse: PendingBlobsResponseDTO = client.get("/blobs/pending")
			async let friendsResponse: FriendListResponseDTO = client.get("/friends")

			let mapFriends = try await mapResponse.friends
			let pending = try await pendingResponse.blobs
			let friendSummaries = try await friendsResponse.friends

			let publicKeys = Dictionary(
				uniqueKeysWithValues: friendSummaries.compactMap { friend -> (String, String)? in
					guard let key = friend.publicKey, !key.isEmpty else { return nil }
					return (friend.userId, key)
				}
			)

			var locationsBySender: [String: (payload: LocationPayloadDTO, updatedAt: Date)] = [:]
			if let myUserId {
				for blob in pending where blob.kind.uppercased() == "LOCATION" {
					guard let senderKey = publicKeys[blob.senderUserId] else { continue }
					do {
						let payload = try await crypto.openLocation(
							ciphertextBase64: blob.ciphertext,
							senderUserId: blob.senderUserId,
							recipientUserId: myUserId,
							senderPublicKeyBase64: senderKey,
							recipientKeyVersion: blob.keyVersion
						)
						let existing = locationsBySender[blob.senderUserId]
						if existing == nil || blob.updatedAt >= (existing?.updatedAt ?? .distantPast) {
							locationsBySender[blob.senderUserId] = (payload, blob.updatedAt)
						}
					} catch {
						continue
					}
				}
			}

			let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
			let mapped: [MapPerson] = mapFriends.compactMap { friend in
				guard let location = locationsBySender[friend.userId] else { return nil }
				return Self.makePerson(
					from: friend,
					payload: location.payload,
					blobUpdatedAt: friend.blobUpdatedAt ?? location.updatedAt,
					origin: originLocation
				)
			}
			.sorted { $0.distanceMeters < $1.distanceMeters }

			friends = mapped
			lastRefreshedAt = Date()

			if let selectedFriendID, !mapped.contains(where: { $0.id == selectedFriendID }) {
				self.selectedFriendID = nil
			}
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	func select(_ friendID: String?) {
		selectedFriendID = friendID
	}

	func clearSelection() {
		selectedFriendID = nil
	}

	func reset() {
		friends = []
		selectedFriendID = nil
		lastErrorMessage = nil
		lastRefreshedAt = nil
		isLoading = false
	}

	// MARK: - Mapping

	private static func makePerson(
		from friend: MapFriendDTO,
		payload: LocationPayloadDTO,
		blobUpdatedAt: Date,
		origin: CLLocation
	) -> MapPerson {
		let coordinate = CLLocationCoordinate2D(latitude: payload.lat, longitude: payload.lon)
		let distance = origin.distance(
			from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
		)
		let availability = friend.availability.status.mapAvailability
		let presence = PresenceState.from(availabilityStatus: friend.availability.status)
		let walking = formattedWalkingMinutes(distanceMeters: distance)
		let interestsList = Array(friend.sharedInterests.prefix(4))
		let interests = interestsList.prefix(2).joined(separator: ", ")

		return MapPerson(
			id: friend.userId,
			displayName: friend.displayName?.isEmpty == false ? (friend.displayName ?? "Friend") : "Friend",
			coordinate: coordinate,
			availability: availability,
			presenceState: presence,
			distanceMeters: distance,
			sharedInterests: interestsList,
			insightSummary: insightSummary(
				availability: friend.availability,
				walking: walking,
				blobUpdatedAt: blobUpdatedAt
			),
			intentLabel: intentLabel(availability: availability, interests: interests),
			neighborhoodLabel: neighborhoodLabel(blobUpdatedAt: blobUpdatedAt, accuracy: payload.accuracy),
			mutualFriendCount: 0,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: ctaTitle(for: availability),
			ctaSystemImage: ctaSystemImage(for: availability)
		)
	}

	private static func insightSummary(
		availability: AvailabilitySnapshotDTO,
		walking: String,
		blobUpdatedAt: Date
	) -> String {
		let seen = RelativeDateTimeFormatter.named.localizedString(for: blobUpdatedAt, relativeTo: Date())
		switch availability.status {
		case .free:
			if let until = availability.freeUntil {
				let time = until.formatted(date: .omitted, time: .shortened)
				return "Free until \(time).\n\(walking). Last seen \(seen)."
			}
			return "Free right now.\n\(walking). Last seen \(seen)."
		case .busy:
			if let freeFrom = availability.freeFrom {
				let when = RelativeDateTimeFormatter.named.localizedString(for: freeFrom, relativeTo: Date())
				return "Busy — free \(when).\n\(walking). Last seen \(seen)."
			}
			return "Busy right now.\n\(walking). Last seen \(seen)."
		case .unknown:
			return "Nearby — status unclear.\n\(walking). Last seen \(seen)."
		}
	}

	private static func intentLabel(availability: MapAvailability, interests: String) -> String {
		let interestSuffix = interests.isEmpty ? nil : interests
		switch availability {
		case .free:
			if let interestSuffix {
				return "Free to hang • \(interestSuffix)"
			}
			return "Free to hang"
		case .busy:
			if let interestSuffix {
				return "Busy • \(interestSuffix)"
			}
			return "Busy • Back later"
		case .unknown:
			if let interestSuffix {
				return "Nearby • \(interestSuffix)"
			}
			return "Nearby • Open to plans"
		}
	}

	private static func neighborhoodLabel(blobUpdatedAt: Date, accuracy: Double?) -> String {
		let seen = RelativeDateTimeFormatter.named.localizedString(for: blobUpdatedAt, relativeTo: Date())
		if let accuracy, accuracy > 0, accuracy < 5_000 {
			return "Live location · \(Int(accuracy.rounded()))m accuracy · \(seen)"
		}
		return "Live location · updated \(seen)"
	}

	private static func ctaTitle(for availability: MapAvailability) -> String {
		switch availability {
		case .free, .unknown: "Say hi nearby"
		case .busy: "Ping when free"
		}
	}

	private static func ctaSystemImage(for availability: MapAvailability) -> String {
		switch availability {
		case .free, .unknown: "hand.wave.fill"
		case .busy: "hourglass"
		}
	}

	private static func formattedWalkingMinutes(distanceMeters: CLLocationDistance) -> String {
		let minutes = max(1, Int((distanceMeters / 80).rounded()))
		if distanceMeters < 1000 {
			return "\(Int(distanceMeters.rounded()))m · \(minutes) mins away"
		}
		return String(format: "%.1fkm · %d mins away", distanceMeters / 1000, minutes)
	}
}

private extension RelativeDateTimeFormatter {
	static let named: RelativeDateTimeFormatter = {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .full
		return formatter
	}()
}
