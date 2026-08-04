import Foundation

/// Wire / domain types for Bump. Transport and ranging stay free of networking and UI.

enum BumpPhase: String, Sendable, Equatable {
	case idle
	case permissioning
	case browsing
	case peerFound
	case inviting
	case invited
	case handshaking
	case ranging
	case persisting
	case paired
	case failed
	case cancelled
}

struct BumpHandshakePayload: Codable, Sendable, Equatable {
	var userId: String
	var displayName: String
	var publicKey: String
	var keyVersion: Int
	var appVersion: String
}

struct BumpDiscoveredPeer: Identifiable, Sendable, Hashable {
	var id: String { peerIDDisplayName }
	var peerIDDisplayName: String
	var discoveryInfo: [String: String]
}

struct NearbyRangeSample: Sendable, Equatable {
	/// Meters. Nil while UWB has not produced a fix yet.
	var distance: Float?
	/// Unit vector in the local device frame when available; nil on distance-only devices/poses.
	var direction: SIMD3<Float>?
	var timestamp: Date
}

enum BumpWireMessageType: String, Codable, Sendable {
	case handshake
	case niToken
	case pairAck
}

/// Versioned Multipeer payload. Keep this the only on-the-wire schema for Bump data.
struct BumpWireEnvelope: Codable, Sendable, Equatable {
	var v: Int
	var type: BumpWireMessageType
	var handshake: BumpHandshakePayload?
	/// Base64 of `NSKeyedArchiver` data for `NIDiscoveryToken`.
	var tokenBase64: String?
	var peerUserId: String?

	static let currentVersion = 1
}

enum BumpTransportError: LocalizedError, Sendable, Equatable {
	case notStarted
	case notConnected
	case inviteTimedOut
	case peerUnavailable
	case encodingFailed
	case decodingFailed(String)
	case unsupportedMessageVersion(Int)
	case rangingUnsupported
	case rangingNotStarted
	case invalidDiscoveryToken

	var errorDescription: String? {
		switch self {
		case .notStarted:
			return "Bump discovery has not started."
		case .notConnected:
			return "Not connected to a nearby peer."
		case .inviteTimedOut:
			return "The invite timed out. Try again."
		case .peerUnavailable:
			return "That peer is no longer available."
		case .encodingFailed:
			return "Could not encode the Bump message."
		case .decodingFailed(let detail):
			return "Could not read a Bump message (\(detail))."
		case .unsupportedMessageVersion(let version):
			return "Unsupported Bump message version (\(version))."
		case .rangingUnsupported:
			return "Ultra Wideband ranging is not available on this device."
		case .rangingNotStarted:
			return "Ranging has not started."
		case .invalidDiscoveryToken:
			return "Invalid nearby discovery token."
		}
	}
}

/// Fired after local consent + server persistence succeed. Presence / Pulse may observe later.
struct BumpPairingSucceededEvent: Sendable, Equatable {
	var peerUserId: String
	var peerDisplayName: String
	var peerPublicKey: String
}
