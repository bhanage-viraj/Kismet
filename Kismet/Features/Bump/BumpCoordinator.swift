import Foundation
import NearbyInteraction
import Observation
import SwiftUI

/// Owns the Bump ceremony state machine. Multipeer + NI stay behind transport helpers;
/// HTTP goes only through `FriendsStore.pairViaBump`.
@Observable
@MainActor
final class BumpCoordinator {
	private(set) var phase: BumpPhase = .idle
	private(set) var discoveredPeers: [BumpDiscoveredPeer] = []
	private(set) var selectedPeerDisplayName: String?
	private(set) var incomingInviteFrom: String?
	private(set) var connectedPeerDisplayName: String?
	private(set) var peerHandshake: BumpHandshakePayload?
	private(set) var rangeSample: NearbyRangeSample?
	private(set) var lastErrorMessage: String?
	private(set) var statusMessage: String?
	private(set) var rangingUnsupported = false
	private(set) var isAlreadyFriends = false
	private(set) var pairedEvent: BumpPairingSucceededEvent?

	private let userId: String
	private let displayName: String
	private let friendsStore: FriendsStore
	private let client: APIClient

	private var transport: MultipeerBumpTransport?
	private var ranging: NearbyRangingSession?
	private var pendingInvitationRespond: (@MainActor (Bool) -> Void)?
	private var sentHandshake = false
	private var receivedHandshake = false
	private var sentNIToken = false
	private var receivedNIToken = false
	private var peerDiscoveryToken: NIDiscoveryToken?
	private var persistTask: Task<Void, Never>?
	/// At most one automatic re-invite after a timeout (plan: then manual retry).
	private var inviteAutoRetriesUsed = 0
	private var lastInvitePeerDisplayName: String?

	init(
		userId: String,
		displayName: String,
		friendsStore: FriendsStore,
		client: APIClient = .shared
	) {
		self.userId = userId
		self.displayName = displayName
		self.friendsStore = friendsStore
		self.client = client
	}

	var canRetryPersist: Bool { phase == .failed && peerHandshake != nil }

	func handleScenePhase(_ scenePhase: ScenePhase) {
		guard scenePhase != .active else { return }
		guard phase != .idle, phase != .paired, phase != .cancelled else { return }
		cancel(message: "Come back and tap Bump again.")
	}

	func start() async {
		guard phase == .idle || phase == .failed || phase == .cancelled || phase == .paired else { return }
		resetSessionState(keepTransport: false)
		phase = .permissioning
		statusMessage = "Preparing secure keys…"
		lastErrorMessage = nil

		do {
			_ = try await CryptoBox.shared.ensurePublished(using: client)
		} catch {
			phase = .failed
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			return
		}

		let transport = MultipeerBumpTransport(preferredDisplayName: displayName)
		wireTransport(transport)
		self.transport = transport
		var info: [String: String] = ["uid": userId]
		let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedName.isEmpty {
			info["name"] = trimmedName
		}
		transport.start(discoveryInfo: info)

		phase = .browsing
		statusMessage = "Looking for nearby phones…"
	}

	func stop() {
		persistTask?.cancel()
		persistTask = nil
		pendingInvitationRespond?(false)
		pendingInvitationRespond = nil
		ranging?.stop()
		ranging = nil
		transport?.stop()
		transport = nil
		resetSessionState(keepTransport: true)
		phase = .idle
		statusMessage = nil
	}

	func cancel(message: String = "Bump cancelled.") {
		persistTask?.cancel()
		persistTask = nil
		pendingInvitationRespond?(false)
		pendingInvitationRespond = nil
		ranging?.stop()
		ranging = nil
		transport?.stop()
		transport = nil
		resetSessionState(keepTransport: true)
		phase = .cancelled
		statusMessage = message
	}

	/// Local consent: tap a discovered peer. Initiator invites; acceptor waits for invite.
	func consentToPeer(_ peer: BumpDiscoveredPeer) {
		guard phase == .browsing || phase == .peerFound || phase == .invited else { return }
		selectedPeerDisplayName = peer.peerIDDisplayName
		lastErrorMessage = nil

		if let incoming = incomingInviteFrom, incoming == peer.peerIDDisplayName {
			acceptIncomingInvite()
			return
		}

		if shouldInitiate(toward: peer) {
			phase = .inviting
			statusMessage = "Waiting for \(peer.peerIDDisplayName) to accept…"
			lastInvitePeerDisplayName = peer.peerIDDisplayName
			transport?.invite(peerDisplayName: peer.peerIDDisplayName)
		} else {
			phase = .invited
			statusMessage = "Waiting for \(peer.peerIDDisplayName) to bump you…"
		}
	}

	func acceptIncomingInvite() {
		guard let respond = pendingInvitationRespond else { return }
		if let name = incomingInviteFrom {
			BumpInviteNotifier.clearInvite(from: name)
		}
		pendingInvitationRespond = nil
		incomingInviteFrom = nil
		phase = .inviting
		statusMessage = "Connecting…"
		respond(true)
	}

	func declineIncomingInvite() {
		if let name = incomingInviteFrom {
			BumpInviteNotifier.clearInvite(from: name)
		}
		pendingInvitationRespond?(false)
		pendingInvitationRespond = nil
		incomingInviteFrom = nil
		selectedPeerDisplayName = nil
		phase = discoveredPeers.isEmpty ? .browsing : .peerFound
		statusMessage = discoveredPeers.isEmpty
			? "Looking for nearby phones…"
			: "Found someone nearby — tap to Bump."
	}

	func retryPersist() {
		guard canRetryPersist, let peer = peerHandshake else { return }
		lastErrorMessage = nil
		phase = .persisting
		statusMessage = "Saving friendship…"
		persistFriendship(with: peer)
	}

	// MARK: - Transport wiring

	private func wireTransport(_ transport: MultipeerBumpTransport) {
		transport.onPeerFound = { [weak self] peer in
			self?.handlePeerFound(peer)
		}
		transport.onPeerLost = { [weak self] name in
			self?.handlePeerLost(name)
		}
		transport.onInviteReceived = { [weak self] from, respond in
			self?.handleInviteReceived(from: from, respond: respond)
		}
		transport.onConnected = { [weak self] name in
			self?.handleConnected(name)
		}
		transport.onDisconnected = { [weak self] name in
			self?.handleDisconnected(name)
		}
		transport.onData = { [weak self] data, from in
			self?.handleData(data, from: from)
		}
		transport.onError = { [weak self] error in
			self?.handleTransportError(error)
		}
	}

	private func handlePeerFound(_ peer: BumpDiscoveredPeer) {
		if !discoveredPeers.contains(where: { $0.peerIDDisplayName == peer.peerIDDisplayName }) {
			discoveredPeers.append(peer)
		}
		if phase == .browsing {
			phase = .peerFound
			statusMessage = "Found someone nearby — tap to Bump."
		}
	}

	private func handlePeerLost(_ name: String) {
		discoveredPeers.removeAll { $0.peerIDDisplayName == name }
		if selectedPeerDisplayName == name, phase == .inviting || phase == .invited {
			selectedPeerDisplayName = nil
			phase = discoveredPeers.isEmpty ? .browsing : .peerFound
			statusMessage = "Peer left. Pick someone nearby again."
		}
		if discoveredPeers.isEmpty, phase == .peerFound {
			phase = .browsing
			statusMessage = "Looking for nearby phones…"
		}
	}

	private func handleInviteReceived(from: String, respond: @escaping @MainActor (Bool) -> Void) {
		// Mutual consent: only auto-accept if we already tapped this peer.
		if selectedPeerDisplayName == from {
			pendingInvitationRespond = nil
			incomingInviteFrom = nil
			respond(true)
			phase = .inviting
			statusMessage = "Connecting…"
			return
		}

		pendingInvitationRespond = respond
		incomingInviteFrom = from
		phase = .invited
		statusMessage = "\(from) wants to Bump — accept?"
		BumpInviteNotifier.notifyIncomingInvite(from: from)
	}

	private func handleConnected(_ name: String) {
		connectedPeerDisplayName = name
		selectedPeerDisplayName = name
		incomingInviteFrom = nil
		pendingInvitationRespond = nil
		phase = .handshaking
		statusMessage = "Exchanging keys…"
		Task { await sendHandshakeIfNeeded() }
	}

	private func handleDisconnected(_ name: String) {
		guard connectedPeerDisplayName == name else { return }
		guard phase != .paired, phase != .cancelled, phase != .idle else { return }
		ranging?.stop()
		phase = .failed
		lastErrorMessage = "Connection lost. Try Bump again."
		statusMessage = nil
	}

	private func handleTransportError(_ error: Error) {
		if let bump = error as? BumpTransportError, bump == .inviteTimedOut {
			if inviteAutoRetriesUsed < 1,
			   let peerName = lastInvitePeerDisplayName,
			   discoveredPeers.contains(where: { $0.peerIDDisplayName == peerName }) {
				inviteAutoRetriesUsed += 1
				selectedPeerDisplayName = peerName
				phase = .inviting
				statusMessage = "Invite timed out — retrying…"
				lastErrorMessage = nil
				transport?.invite(peerDisplayName: peerName)
				return
			}
			phase = discoveredPeers.isEmpty ? .browsing : .peerFound
			lastErrorMessage = bump.errorDescription
			statusMessage = "Invite timed out — tap to try again."
			selectedPeerDisplayName = nil
			return
		}
		phase = .failed
		lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
	}

	private func handleData(_ data: Data, from: String) {
		do {
			let envelope = try BumpHandshakeCodec.decode(data)
			switch envelope.type {
			case .handshake:
				guard let payload = envelope.handshake else { return }
				peerHandshake = payload
				receivedHandshake = true
				statusMessage = "Got \(payload.displayName.isEmpty ? payload.userId : payload.displayName)’s key…"
				Task { await advanceAfterHandshake() }
			case .niToken:
				guard let base64 = envelope.tokenBase64 else { return }
				peerDiscoveryToken = try NearbyRangingSession.decodeDiscoveryToken(base64)
				receivedNIToken = true
				Task { await advanceAfterTokens() }
			case .pairAck:
				finishPairedFromAck()
			}
		} catch {
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	// MARK: - Handshake + ranging + persist

	private func sendHandshakeIfNeeded() async {
		guard !sentHandshake, let transport else { return }
		do {
			let publicKey = try await CryptoBox.shared.publicKeyBase64()
			let keyVersion = await CryptoBox.shared.keyVersion()
			let payload = BumpHandshakePayload(
				userId: userId,
				displayName: displayName.isEmpty ? shortUserId : displayName,
				publicKey: publicKey,
				keyVersion: keyVersion,
				appVersion: Self.appVersion
			)
			let data = try BumpHandshakeCodec.encode(BumpHandshakeCodec.handshakeEnvelope(payload))
			try transport.sendReliable(data, to: connectedPeerDisplayName)
			sentHandshake = true
			await advanceAfterHandshake()
		} catch {
			phase = .failed
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	private func advanceAfterHandshake() async {
		guard sentHandshake, receivedHandshake, let peer = peerHandshake else { return }

		if friendsStore.isFriend(userId: peer.userId) {
			isAlreadyFriends = true
			statusMessage = "Already friends — starting Radar…"
		}

		await beginTokenExchange()
	}

	private func beginTokenExchange() async {
		guard phase == .handshaking || phase == .ranging else { return }

		if !NearbyRangingSession.isSupported {
			rangingUnsupported = true
			statusMessage = "Paired path ready — ranging unavailable on this device."
			await persistOrWait()
			return
		}

		do {
			let session = NearbyRangingSession()
			try session.prepare()
			session.onUpdate = { [weak self] sample in
				self?.rangeSample = sample
			}
			session.onInvalidated = { [weak self] error in
				guard let self, self.phase == .ranging else { return }
				if let error {
					self.lastErrorMessage = error.localizedDescription
				}
			}
			ranging = session

			if !sentNIToken, let token = session.localDiscoveryToken {
				let base64 = try NearbyRangingSession.encodeDiscoveryToken(token)
				let data = try BumpHandshakeCodec.encode(BumpHandshakeCodec.niTokenEnvelope(tokenBase64: base64))
				try transport?.sendReliable(data, to: connectedPeerDisplayName)
				sentNIToken = true
			}
			await advanceAfterTokens()
		} catch {
			rangingUnsupported = true
			lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			await persistOrWait()
		}
	}

	private func advanceAfterTokens() async {
		guard sentNIToken, receivedNIToken, let peerToken = peerDiscoveryToken else { return }
		do {
			try ranging?.run(with: peerToken)
			phase = .ranging
			statusMessage = isAlreadyFriends
				? "Already friends — move phones to see Radar."
				: "Radar live — finishing friendship…"
			await persistOrWait()
		} catch {
			rangingUnsupported = true
			await persistOrWait()
		}
	}

	private func persistOrWait() async {
		guard let peer = peerHandshake else { return }
		if isAlreadyFriends {
			finishAlreadyFriends(peer)
			return
		}

		let peerCard = discoveredPeers.first { $0.peerIDDisplayName == connectedPeerDisplayName }
			?? BumpDiscoveredPeer(peerIDDisplayName: connectedPeerDisplayName ?? "", discoveryInfo: ["uid": peer.userId])

		if shouldInitiate(toward: peerCard) || shouldInitiateByUserId(peer.userId) {
			phase = .persisting
			statusMessage = "Saving friendship…"
			persistFriendship(with: peer)
		} else {
			phase = phase == .ranging ? .ranging : .persisting
			statusMessage = statusMessage ?? "Waiting for friend to confirm…"
		}
	}

	private func persistFriendship(with peer: BumpHandshakePayload) {
		persistTask?.cancel()
		persistTask = Task { @MainActor [weak self] in
			guard let self else { return }
			await friendsStore.pairViaBump(
				peerUserId: peer.userId,
				peerPublicKey: peer.publicKey
			)
			guard !Task.isCancelled else { return }

			if friendsStore.lastErrorMessage != nil {
				phase = .failed
				lastErrorMessage = friendsStore.lastErrorMessage
				statusMessage = "Could not save — tap retry."
				return
			}

			do {
				let data = try BumpHandshakeCodec.encode(
					BumpHandshakeCodec.pairAckEnvelope(peerUserId: peer.userId)
				)
				try transport?.sendReliable(data, to: connectedPeerDisplayName)
			} catch {
				// Persist succeeded even if Multipeer is already dead (offline ack).
				if connectedPeerDisplayName != nil {
					lastErrorMessage = "Saved locally, but could not notify peer. They can pull friends to refresh."
				}
			}

			pairedEvent = BumpPairingSucceededEvent(
				peerUserId: peer.userId,
				peerDisplayName: peer.displayName.isEmpty ? peer.userId : peer.displayName,
				peerPublicKey: peer.publicKey
			)
			phase = .paired
			statusMessage = rangingUnsupported
				? "Friends! Ranging unavailable on this device."
				: "Friends! Radar is live."
		}
	}

	private func finishPairedFromAck() {
		guard let peer = peerHandshake else { return }
		let name = peer.displayName.isEmpty ? peer.userId : peer.displayName
		pairedEvent = BumpPairingSucceededEvent(
			peerUserId: peer.userId,
			peerDisplayName: name,
			peerPublicKey: peer.publicKey
		)
		phase = .paired
		statusMessage = rangingUnsupported
			? "Friends! Ranging unavailable on this device."
			: "Friends! Radar is live."
		Task {
			await friendsStore.noteRemoteBumpPairing(
				peerUserId: peer.userId,
				peerDisplayName: name,
				peerPublicKey: peer.publicKey
			)
		}
	}

	private func finishAlreadyFriends(_ peer: BumpHandshakePayload) {
		pairedEvent = BumpPairingSucceededEvent(
			peerUserId: peer.userId,
			peerDisplayName: peer.displayName.isEmpty ? peer.userId : peer.displayName,
			peerPublicKey: peer.publicKey
		)
		phase = .paired
		statusMessage = rangingUnsupported
			? "Already friends — ranging unavailable on this device."
			: "Already friends — Radar is live."
	}

	// MARK: - Helpers

	private var shortUserId: String {
		String(userId.suffix(6))
	}

	private static var appVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
	}

	private func shouldInitiate(toward peer: BumpDiscoveredPeer) -> Bool {
		let remoteUID = peer.discoveryInfo["uid"] ?? peer.peerIDDisplayName
		if userId != remoteUID {
			return userId < remoteUID
		}
		let localName = transport?.localPeerDisplayName ?? displayName
		return localName < peer.peerIDDisplayName
	}

	private func shouldInitiateByUserId(_ peerUserId: String) -> Bool {
		userId < peerUserId
	}

	private func resetSessionState(keepTransport: Bool) {
		discoveredPeers = []
		selectedPeerDisplayName = nil
		incomingInviteFrom = nil
		connectedPeerDisplayName = nil
		peerHandshake = nil
		rangeSample = nil
		lastErrorMessage = nil
		rangingUnsupported = false
		isAlreadyFriends = false
		pairedEvent = nil
		sentHandshake = false
		receivedHandshake = false
		sentNIToken = false
		receivedNIToken = false
		peerDiscoveryToken = nil
		inviteAutoRetriesUsed = 0
		lastInvitePeerDisplayName = nil
		if !keepTransport {
			statusMessage = nil
		}
	}
}
