import Foundation
import NearbyInteraction

/// NearbyInteraction only — discovery-token exchange helpers + distance / direction updates.
/// No MultipeerConnectivity or HTTP.
@MainActor
final class NearbyRangingSession: NSObject {
	static var isSupported: Bool { NISession.isSupported }

	private var session: NISession?

	private(set) var isRunning = false
	private(set) var latestSample: NearbyRangeSample?

	var onUpdate: ((NearbyRangeSample) -> Void)?
	var onInvalidated: ((Error?) -> Void)?

	/// Local token to send over Multipeer after creating the session.
	var localDiscoveryToken: NIDiscoveryToken? { session?.discoveryToken }

	/// Creates an `NISession` so `localDiscoveryToken` is available for exchange.
	/// Call `run(with:)` only after receiving the peer's token.
	func prepare() throws {
		guard Self.isSupported else { throw BumpTransportError.rangingUnsupported }
		stop()
		let session = NISession()
		session.delegate = self
		self.session = session
	}

	func run(with peerToken: NIDiscoveryToken) throws {
		guard Self.isSupported else { throw BumpTransportError.rangingUnsupported }
		if session == nil {
			try prepare()
		}
		guard let session else { throw BumpTransportError.rangingNotStarted }
		let configuration = NINearbyPeerConfiguration(peerToken: peerToken)
		session.run(configuration)
		isRunning = true
	}

	func stop() {
		session?.invalidate()
		session?.delegate = nil
		session = nil
		isRunning = false
		latestSample = nil
	}

	// MARK: - Token codec (NSKeyedArchiver)

	static func encodeDiscoveryToken(_ token: NIDiscoveryToken) throws -> String {
		let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
		return data.base64EncodedString()
	}

	static func decodeDiscoveryToken(_ base64: String) throws -> NIDiscoveryToken {
		guard let data = Data(base64Encoded: base64) else {
			throw BumpTransportError.invalidDiscoveryToken
		}
		guard let token = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: NIDiscoveryToken.self,
			from: data
		) else {
			throw BumpTransportError.invalidDiscoveryToken
		}
		return token
	}
}

extension NearbyRangingSession: NISessionDelegate {
	nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
		guard let object = nearbyObjects.first else { return }
		let distance = object.distance
		let sample = NearbyRangeSample(
			distance: distance,
			direction: object.direction,
			timestamp: Date()
		)
		Task { @MainActor in
			latestSample = sample
			onUpdate?(sample)
		}
	}

	nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
		Task { @MainActor in
			latestSample = NearbyRangeSample(distance: nil, direction: nil, timestamp: Date())
			if reason == .peerEnded {
				onInvalidated?(nil)
			}
		}
	}

	nonisolated func sessionWasSuspended(_ session: NISession) {
		Task { @MainActor in
			isRunning = false
		}
	}

	nonisolated func sessionSuspensionEnded(_ session: NISession) {
		// Coordinator may call run(with:) again with the last peer token if still connected.
		Task { @MainActor in
			isRunning = true
		}
	}

	nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
		Task { @MainActor in
			isRunning = false
			self.session = nil
			onInvalidated?(error)
		}
	}
}
