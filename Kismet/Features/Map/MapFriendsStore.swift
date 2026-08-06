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
			var sealedInterestsBySender: [String: [String]] = [:]
			var myInterestSet: Set<String> = []
			if let myUserId {
				let interestMatcher = InterestMatchSharingService(client: client, crypto: crypto)
				async let sealed = interestMatcher.loadFriendInterests(friends: friendSummaries)
				async let meResponse: MeResponseDTO = client.get("/me")
				sealedInterestsBySender = await sealed
				if let me = try? await meResponse {
					myInterestSet = Set(me.interests.map { $0.lowercased() })
				}

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
				let e2eeShared: [String]? = {
					guard let theirs = sealedInterestsBySender[friend.userId] else { return nil }
					return Array(myInterestSet.intersection(Set(theirs.map { $0.lowercased() }))).sorted()
				}()
				return Self.makePerson(
					from: friend,
					payload: location.payload,
					blobUpdatedAt: friend.blobUpdatedAt ?? location.updatedAt,
					origin: originLocation,
					sharedInterestsOverride: e2eeShared
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
		origin: CLLocation,
		sharedInterestsOverride: [String]? = nil
	) -> MapPerson? {
		let presence = PresenceState.from(
			payload: payload,
			availabilityStatus: friend.availability.status
		)
		// Eclipse: hidden from map / suggestions / proximity surfaces.
		guard presence.isSurfaceVisible else { return nil }

		let coordinate = CLLocationCoordinate2D(latitude: payload.lat, longitude: payload.lon)
		let distance = origin.distance(
			from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
		)
		let availability = presence.mapAvailability
		let walking = formattedWalkingMinutes(distanceMeters: distance, presence: presence)
		let interestsList = Array((sharedInterestsOverride ?? friend.sharedInterests).prefix(4))
		let interests = interestsList.prefix(2).joined(separator: ", ")

		return MapPerson(
			id: friend.userId,
			displayName: friend.displayName?.isEmpty == false ? (friend.displayName ?? "Friend") : "Friend",
			coordinate: coordinate,
			availability: availability,
			presenceState: presence,
			distanceMeters: distance,
			sharedInterests: interestsList,
			freeUntil: friend.availability.freeUntil,
			freeFrom: friend.availability.freeFrom,
			insightSummary: insightSummary(
				presence: presence,
				availability: friend.availability,
				walking: walking,
				blobUpdatedAt: blobUpdatedAt
			),
			intentLabel: intentLabel(presence: presence, interests: interests),
			neighborhoodLabel: neighborhoodLabel(
				presence: presence,
				blobUpdatedAt: blobUpdatedAt,
				accuracy: payload.accuracy
			),
			mutualFriendCount: 0,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: ctaTitle(for: presence),
			ctaSystemImage: ctaSystemImage(for: presence)
		)
	}

	private static func insightSummary(
		presence: PresenceState,
		availability: AvailabilitySnapshotDTO,
		walking: String,
		blobUpdatedAt: Date
	) -> String {
		let seen = RelativeDateTimeFormatter.named.localizedString(for: blobUpdatedAt, relativeTo: Date())
		switch presence {
		case .available:
			if let until = availability.freeUntil {
				let time = until.formatted(date: .omitted, time: .shortened)
				return "Available until \(time).\n\(walking). Last seen \(seen)."
			}
			return "Available right now.\n\(walking). Last seen \(seen)."
		case .friendsOnly:
			return "Friends only.\n\(walking). Last seen \(seen)."
		case .approximate:
			return "Approximate location.\nNearby. Last seen \(seen)."
		case .eclipse:
			return "Hidden.\nLast seen \(seen)."
		}
	}

	private static func intentLabel(presence: PresenceState, interests: String) -> String {
		let interestSuffix = interests.isEmpty ? nil : interests
		switch presence {
		case .available:
			if let interestSuffix {
				return "Available • \(interestSuffix)"
			}
			return "Available to hang"
		case .friendsOnly:
			if let interestSuffix {
				return "Friends only • \(interestSuffix)"
			}
			return "Friends only"
		case .approximate:
			if let interestSuffix {
				return "Nearby • \(interestSuffix)"
			}
			return "Nearby • Open to plans"
		case .eclipse:
			return "Hidden"
		}
	}

	private static func neighborhoodLabel(
		presence: PresenceState,
		blobUpdatedAt: Date,
		accuracy: Double?
	) -> String {
		let seen = RelativeDateTimeFormatter.named.localizedString(for: blobUpdatedAt, relativeTo: Date())
		if !presence.showsPreciseLocation {
			return "Approximate location · updated \(seen)"
		}
		if let accuracy, accuracy > 0, accuracy < 5_000 {
			return "Live location · \(Int(accuracy.rounded()))m accuracy · \(seen)"
		}
		return "Live location · updated \(seen)"
	}

	private static func ctaTitle(for presence: PresenceState) -> String {
		switch presence {
		case .available, .approximate: "Say hi nearby"
		case .friendsOnly: "Ping a friend"
		case .eclipse: "Hidden"
		}
	}

	private static func ctaSystemImage(for presence: PresenceState) -> String {
		switch presence {
		case .available, .approximate: "hand.wave.fill"
		case .friendsOnly: "person.2.fill"
		case .eclipse: "moon.fill"
		}
	}

	private static func formattedWalkingMinutes(
		distanceMeters: CLLocationDistance,
		presence: PresenceState
	) -> String {
		guard presence.showsPreciseLocation else { return "Nearby" }
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
