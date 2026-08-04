import Foundation
import MultipeerConnectivity

/// MultipeerConnectivity only — advertise, browse, invite, reliable data, teardown.
/// No CryptoKit, NearbyInteraction, or HTTP.
@MainActor
final class MultipeerBumpTransport: NSObject {
	/// Must match `NSBonjourServices` entry `_bump._tcp` (without the `_` / `._tcp` wrapper).
	static let serviceType = "bump"
	static let defaultInviteTimeout: TimeInterval = 15

	private static let peerDisplayNameDefaultsKey = "bump.mcPeerDisplayName"

	private let myPeerID: MCPeerID

	private var session: MCSession?
	private var advertiser: MCNearbyServiceAdvertiser?
	private var browser: MCNearbyServiceBrowser?

	private var inviteTimeoutTask: Task<Void, Never>?
	private var pendingInvitePeer: MCPeerID?

	private(set) var isRunning = false
	private(set) var connectedPeers: Set<MCPeerID> = []

	var onPeerFound: ((BumpDiscoveredPeer) -> Void)?
	var onPeerLost: ((String) -> Void)?
	var onInviteReceived: ((_ fromDisplayName: String, _ respond: @escaping @MainActor (Bool) -> Void) -> Void)?
	var onConnected: ((String) -> Void)?
	var onDisconnected: ((String) -> Void)?
	var onData: ((Data, String) -> Void)?
	var onError: ((Error) -> Void)?

	/// - Parameter preferredDisplayName: Stable human-readable label. Persisted for the install
	///   so `MCPeerID` recreation stays recognizable across launches (ceremony is still per-session).
	init(preferredDisplayName: String) {
		let name = Self.resolvedPeerDisplayName(preferred: preferredDisplayName)
		myPeerID = MCPeerID(displayName: name)
		super.init()
	}

	var localPeerDisplayName: String { myPeerID.displayName }

	func start(discoveryInfo: [String: String]? = nil) {
		stop()
		isRunning = true

		let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
		session.delegate = self
		self.session = session

		let advertiser = MCNearbyServiceAdvertiser(
			peer: myPeerID,
			discoveryInfo: discoveryInfo,
			serviceType: Self.serviceType
		)
		advertiser.delegate = self
		self.advertiser = advertiser
		advertiser.startAdvertisingPeer()

		let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
		browser.delegate = self
		self.browser = browser
		browser.startBrowsingForPeers()
	}

	func stop() {
		inviteTimeoutTask?.cancel()
		inviteTimeoutTask = nil
		pendingInvitePeer = nil

		advertiser?.stopAdvertisingPeer()
		advertiser?.delegate = nil
		advertiser = nil

		browser?.stopBrowsingForPeers()
		browser?.delegate = nil
		browser = nil

		session?.disconnect()
		session?.delegate = nil
		session = nil

		connectedPeers.removeAll()
		isRunning = false
	}

	func invite(
		peerDisplayName: String,
		timeout: TimeInterval = MultipeerBumpTransport.defaultInviteTimeout
	) {
		guard let browser, let session else {
			onError?(BumpTransportError.notStarted)
			return
		}
		guard let peer = browserKnownPeers[peerDisplayName] else {
			onError?(BumpTransportError.peerUnavailable)
			return
		}

		inviteTimeoutTask?.cancel()
		pendingInvitePeer = peer
		browser.invitePeer(peer, to: session, withContext: nil, timeout: timeout)

		inviteTimeoutTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(timeout))
			guard let self, !Task.isCancelled else { return }
			guard self.pendingInvitePeer == peer, !self.connectedPeers.contains(peer) else { return }
			self.pendingInvitePeer = nil
			self.onError?(BumpTransportError.inviteTimedOut)
		}
	}

	func sendReliable(_ data: Data, to peerDisplayName: String? = nil) throws {
		guard let session else { throw BumpTransportError.notStarted }
		let targets: [MCPeerID]
		if let peerDisplayName {
			guard let peer = connectedPeers.first(where: { $0.displayName == peerDisplayName }) else {
				throw BumpTransportError.notConnected
			}
			targets = [peer]
		} else {
			targets = Array(connectedPeers)
			guard !targets.isEmpty else { throw BumpTransportError.notConnected }
		}
		try session.send(data, toPeers: targets, with: .reliable)
	}

	func disconnect() {
		session?.disconnect()
		connectedPeers.removeAll()
	}

	// MARK: - Peer map (browser discoveries)

	private var browserKnownPeers: [String: MCPeerID] = [:]

	private static func resolvedPeerDisplayName(preferred: String) -> String {
		if let stored = UserDefaults.standard.string(forKey: peerDisplayNameDefaultsKey),
		   !stored.isEmpty {
			return String(stored.prefix(63))
		}
		let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
		let base: String
		if trimmed.isEmpty {
			base = "Kismet-\(String(UUID().uuidString.prefix(4)))"
		} else {
			base = trimmed
		}
		let clipped = String(base.prefix(63))
		UserDefaults.standard.set(clipped, forKey: peerDisplayNameDefaultsKey)
		return clipped
	}
}

// MARK: - MCSessionDelegate

extension MultipeerBumpTransport: MCSessionDelegate {
	nonisolated func session(
		_ session: MCSession,
		peer peerID: MCPeerID,
		didChange state: MCSessionState
	) {
		Task { @MainActor in
			switch state {
			case .connected:
				inviteTimeoutTask?.cancel()
				inviteTimeoutTask = nil
				pendingInvitePeer = nil
				connectedPeers.insert(peerID)
				onConnected?(peerID.displayName)
			case .notConnected:
				connectedPeers.remove(peerID)
				onDisconnected?(peerID.displayName)
			case .connecting:
				break
			@unknown default:
				break
			}
		}
	}

	nonisolated func session(
		_ session: MCSession,
		didReceive data: Data,
		fromPeer peerID: MCPeerID
	) {
		Task { @MainActor in
			onData?(data, peerID.displayName)
		}
	}

	nonisolated func session(
		_ session: MCSession,
		didReceive stream: InputStream,
		withName streamName: String,
		fromPeer peerID: MCPeerID
	) {}

	nonisolated func session(
		_ session: MCSession,
		didStartReceivingResourceWithName resourceName: String,
		fromPeer peerID: MCPeerID,
		with progress: Progress
	) {}

	nonisolated func session(
		_ session: MCSession,
		didFinishReceivingResourceWithName resourceName: String,
		fromPeer peerID: MCPeerID,
		at localURL: URL?,
		withError error: Error?
	) {}
}

// MARK: - Advertiser

extension MultipeerBumpTransport: MCNearbyServiceAdvertiserDelegate {
	nonisolated func advertiser(
		_ advertiser: MCNearbyServiceAdvertiser,
		didReceiveInvitationFromPeer peerID: MCPeerID,
		withContext context: Data?,
		invitationHandler: @escaping (Bool, MCSession?) -> Void
	) {
		Task { @MainActor in
			guard let session = self.session else {
				invitationHandler(false, nil)
				return
			}
			let respond: @MainActor (Bool) -> Void = { accepted in
				invitationHandler(accepted, accepted ? session : nil)
			}
			if let onInviteReceived {
				onInviteReceived(peerID.displayName, respond)
			} else {
				// Fail closed: mutual consent must be explicit in the coordinator.
				respond(false)
			}
		}
	}

	nonisolated func advertiser(
		_ advertiser: MCNearbyServiceAdvertiser,
		didNotStartAdvertisingPeer error: Error
	) {
		Task { @MainActor in
			onError?(error)
		}
	}
}

// MARK: - Browser

extension MultipeerBumpTransport: MCNearbyServiceBrowserDelegate {
	nonisolated func browser(
		_ browser: MCNearbyServiceBrowser,
		foundPeer peerID: MCPeerID,
		withDiscoveryInfo info: [String: String]?
	) {
		Task { @MainActor in
			guard peerID != myPeerID else { return }
			browserKnownPeers[peerID.displayName] = peerID
			onPeerFound?(
				BumpDiscoveredPeer(
					peerIDDisplayName: peerID.displayName,
					discoveryInfo: info ?? [:]
				)
			)
		}
	}

	nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		Task { @MainActor in
			browserKnownPeers.removeValue(forKey: peerID.displayName)
			onPeerLost?(peerID.displayName)
		}
	}

	nonisolated func browser(
		_ browser: MCNearbyServiceBrowser,
		didNotStartBrowsingForPeers error: Error
	) {
		Task { @MainActor in
			onError?(error)
		}
	}
}
