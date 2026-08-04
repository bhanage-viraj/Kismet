import Foundation

// MARK: - Map

struct MapFriendsResponseDTO: Decodable, Sendable {
	var friends: [MapFriendDTO]
}

struct MapFriendDTO: Decodable, Sendable, Identifiable {
	var userId: String
	var displayName: String?
	var availability: AvailabilitySnapshotDTO
	var sharedInterests: [String]
	var hasLocationBlob: Bool
	var blobUpdatedAt: Date?

	var id: String { userId }
}

struct AvailabilitySnapshotDTO: Decodable, Sendable {
	var status: AvailabilityStatusDTO
	var freeUntil: Date?
	var freeFrom: Date?
}

enum AvailabilityStatusDTO: String, Codable, Sendable {
	case free = "FREE"
	case busy = "BUSY"
	case unknown = "UNKNOWN"

	var mapAvailability: MapAvailability {
		switch self {
		case .free: .free
		case .busy: .busy
		case .unknown: .unknown
		}
	}
}

// MARK: - Friends

struct FriendListResponseDTO: Decodable, Sendable {
	var friends: [FriendSummaryDTO]
}

struct FriendSummaryDTO: Decodable, Sendable, Identifiable {
	var pairId: String
	var userId: String
	var displayName: String?
	var publicKey: String?
	var keyVersion: Int
	var status: String
	var connectedVia: String?
	var since: Date?
	var initiatedByMe: Bool

	var id: String { userId }
}

struct InviteCodeResponseDTO: Decodable, Sendable {
	var code: String
	var qrPayload: String
	var expiresAt: Date
}

struct RedeemInviteRequestDTO: Encodable, Sendable {
	var inviteCode: String
}

struct BumpPairRequestDTO: Encodable, Sendable {
	var peerUserId: String
	var peerPublicKey: String?
}

// MARK: - Blobs

struct BlobUploadRequestDTO: Encodable, Sendable {
	var blobs: [CreateBlobRequestDTO]
}

struct CreateBlobRequestDTO: Encodable, Sendable {
	var recipientUserId: String
	var kind: String
	var ciphertext: String
	var keyVersion: Int
}

struct BlobUploadResponseDTO: Decodable, Sendable {
	var accepted: Int
	var expiresAt: Date
}

struct PendingBlobsResponseDTO: Decodable, Sendable {
	var blobs: [PendingBlobDTO]
}

struct PendingBlobDTO: Decodable, Sendable, Identifiable {
	var id: String
	var senderUserId: String
	var kind: String
	var ciphertext: String
	var keyVersion: Int
	var updatedAt: Date
}

struct BlobAckRequestDTO: Encodable, Sendable {
	var blobIds: [String]
}

struct BlobAckResponseDTO: Decodable, Sendable {
	var deleted: Int64
}

// MARK: - Keys / timezone

struct PublicKeyRequestDTO: Encodable, Sendable {
	var publicKey: String
	var keyVersion: Int
}

struct TimeZoneRequestDTO: Encodable, Sendable {
	var timeZoneId: String
}

// MARK: - Location plaintext (client-only, sealed inside ciphertext)

struct LocationPayloadDTO: Codable, Sendable {
	var lat: Double
	var lon: Double
	var accuracy: Double?
	var at: Date
}
