import SwiftUI
import UIKit

/// Nearby Multipeer pairing flow (opened from More → Add nearby friend).
struct BumpFlowView: View {
	@Environment(AuthSession.self) private var authSession
	@Environment(FriendsStore.self) private var friendsStore
	@Environment(\.scenePhase) private var scenePhase
	@Environment(\.openURL) private var openURL

	@State private var coordinator: BumpCoordinator?
	@State private var consentPresentation: ConsentPresentation?
	@State private var startFailedMessage: String?

	var body: some View {
		Group {
			if let coordinator {
				radarContent(coordinator)
			} else if let startFailedMessage {
				startupError(startFailedMessage)
			} else {
				ProgressView("Looking for people…")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.task {
			BumpInviteNotifier.requestAuthorizationIfNeeded()
			BumpInviteNotifier.registerCategories()
			if friendsStore.friends.isEmpty {
				await friendsStore.refresh()
			}
			await ensureCoordinator()
		}
		.onChange(of: scenePhase) { _, newPhase in
			coordinator?.handleScenePhase(newPhase)
		}
		.onChange(of: coordinator?.incomingInviteFrom ?? "") { _, incoming in
			guard !incoming.isEmpty, let coordinator else { return }
			consentPresentation = makePresentation(
				peerDisplayName: incoming,
				distanceMeters: nil,
				direction: .incoming,
				coordinator: coordinator
			)
		}
		.sheet(item: $consentPresentation) { presentation in
			BumpConsentView(
				details: presentation.details,
				onAccept: { handleConsentAccept(presentation) },
				onDecline: { handleConsentDecline(presentation) }
			)
			.presentationDetents([.large])
			.presentationDragIndicator(.visible)
		}
		.onDisappear {
			coordinator?.stop()
			coordinator = nil
		}
	}

	// MARK: - Radar

	@ViewBuilder
	private func radarContent(_ coordinator: BumpCoordinator) -> some View {
		ZStack(alignment: .top) {
			NearbyRadarView(
				friends: radarFriends(from: coordinator),
				selectedFriendId: consentPresentation?.peerDisplayName
					?? coordinator.selectedPeerDisplayName,
				isSearching: isSearching(coordinator),
				onSelectFriend: { friend in
					guard let peer = coordinator.discoveredPeers.first(where: { $0.peerIDDisplayName == friend.id })
					else { return }
					guard !isExistingFriend(peer) else { return }
					consentPresentation = makePresentation(
						peerDisplayName: peer.peerIDDisplayName,
						distanceMeters: friend.distanceMeters,
						direction: .outgoing,
						coordinator: coordinator
					)
				}
			)

			if let bannerText = bannerText(for: coordinator) {
				Text(bannerText)
					.font(.footnote.weight(.medium))
					.foregroundStyle(coordinator.lastErrorMessage != nil ? Color.red : Color.primary)
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.padding(.top, 8)
					.padding(.horizontal, 20)
					.accessibilityAddTraits(.isStaticText)
			}
		}
		.toolbar {
			if coordinator.phase == .paired {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") {
						Task { await restartCoordinator() }
					}
				}
			} else if coordinator.phase != .idle, coordinator.phase != .browsing, coordinator.phase != .peerFound {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Cancel") {
						coordinator.cancel()
						consentPresentation = nil
						Task { await restartCoordinator() }
					}
				}
			}
		}
	}

	private func startupError(_ message: String) -> some View {
		ContentUnavailableView {
			Label("Radar unavailable", systemImage: "exclamationmark.triangle")
		} description: {
			Text(message)
		} actions: {
			Button("Try again") {
				startFailedMessage = nil
				Task { await ensureCoordinator() }
			}
			.buttonStyle(.borderedProminent)
			Button("Open Settings") {
				if let url = URL(string: UIApplication.openSettingsURLString) {
					openURL(url)
				}
			}
			.buttonStyle(.bordered)
		}
	}

	// MARK: - Consent

	private func makePresentation(
		peerDisplayName: String,
		distanceMeters: Double?,
		direction: ConsentDirection,
		coordinator: BumpCoordinator
	) -> ConsentPresentation {
		let peer = coordinator.discoveredPeers.first { $0.peerIDDisplayName == peerDisplayName }
			?? BumpDiscoveredPeer(peerIDDisplayName: peerDisplayName, discoveryInfo: [:])
		let uid = peer.discoveryInfo["uid"]
		let friend = friendsStore.friends.first { summary in
			if let uid, summary.userId == uid { return true }
			if let name = summary.displayName, name == peerDisplayName { return true }
			return false
		}
		let details = BumpPeerDetails.from(
			peer: peer,
			distanceMeters: distanceMeters,
			friend: friend
		)
		return ConsentPresentation(
			peerDisplayName: peerDisplayName,
			direction: direction,
			details: details
		)
	}

	private func handleConsentAccept(_ presentation: ConsentPresentation) {
		guard let coordinator else {
			consentPresentation = nil
			return
		}

		switch presentation.direction {
		case .outgoing:
			if let peer = coordinator.discoveredPeers.first(where: {
				$0.peerIDDisplayName == presentation.peerDisplayName
			}) {
				coordinator.consentToPeer(peer)
			}
		case .incoming:
			coordinator.acceptIncomingInvite()
		}
		consentPresentation = nil
	}

	private func handleConsentDecline(_ presentation: ConsentPresentation) {
		guard let coordinator else {
			consentPresentation = nil
			return
		}
		if presentation.direction == .incoming {
			coordinator.declineIncomingInvite()
		}
		consentPresentation = nil
	}

	// MARK: - Mapping

	private func radarFriends(from coordinator: BumpCoordinator) -> [RadarFriend] {
		// Radar is for new connections only — hide anyone already in FriendsStore.
		let strangers = coordinator.discoveredPeers.filter { !isExistingFriend($0) }
		guard !strangers.isEmpty else { return [] }

		return strangers.enumerated().map { index, peer in
			let angle = peerBearing(index: index, total: strangers.count, peerName: peer.peerIDDisplayName)
			let isFocused = peer.peerIDDisplayName == coordinator.connectedPeerDisplayName
				|| peer.peerIDDisplayName == coordinator.selectedPeerDisplayName
			let uid = peer.discoveryInfo["uid"]
			let distance: Double

			if isFocused, let meters = coordinator.rangeSample?.distance {
				distance = min(Double(meters) * 80, 480)
			} else {
				distance = 180 + Double((index * 70) % 280)
			}

			let discoveryName = peer.discoveryInfo["name"]?
				.trimmingCharacters(in: .whitespacesAndNewlines)
			let name = [discoveryName, peer.peerIDDisplayName]
				.compactMap { $0 }
				.first { !$0.isEmpty } ?? peer.peerIDDisplayName

			return RadarFriend(
				id: peer.peerIDDisplayName,
				name: name,
				distanceMeters: distance,
				bearingRadians: angle,
				presence: .available,
				userId: uid
			)
		}
	}

	private func isExistingFriend(_ peer: BumpDiscoveredPeer) -> Bool {
		let uid = peer.discoveryInfo["uid"]
		if let uid, friendsStore.friends.contains(where: { $0.userId == uid }) {
			return true
		}
		let discoveryName = peer.discoveryInfo["name"]?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let names = [discoveryName, peer.peerIDDisplayName].compactMap { $0 }
		return friendsStore.friends.contains { friend in
			guard let friendName = friend.displayName else { return false }
			return names.contains { $0.caseInsensitiveCompare(friendName) == .orderedSame }
		}
	}

	/// Stable-ish fan-out so peers don't stack on the same blip.
	private func peerBearing(index: Int, total: Int, peerName: String) -> Double {
		if total == 1 { return -.pi / 2 }
		let hash = abs(peerName.hashValue)
		let jitter = Double(hash % 40) / 100.0 - 0.2
		let step = (2 * Double.pi) / Double(total)
		return -Double.pi / 2 + step * Double(index) + jitter
	}

	private func isSearching(_ coordinator: BumpCoordinator) -> Bool {
		switch coordinator.phase {
		case .permissioning, .browsing, .peerFound:
			true
		default:
			false
		}
	}

	private func bannerText(for coordinator: BumpCoordinator) -> String? {
		if let error = coordinator.lastErrorMessage { return error }
		switch coordinator.phase {
		case .permissioning:
			return "Preparing secure keys…"
		case .browsing:
			let strangers = coordinator.discoveredPeers.filter { !isExistingFriend($0) }
			if strangers.isEmpty {
				return coordinator.discoveredPeers.isEmpty
					? "Looking for nearby phones…"
					: "No new people nearby — only existing friends."
			}
			return nil
		case .peerFound:
			let strangers = coordinator.discoveredPeers.filter { !isExistingFriend($0) }
			return strangers.isEmpty ? "No new people nearby — only existing friends." : nil
		case .inviting:
			return coordinator.statusMessage
		case .handshaking, .ranging, .persisting:
			return coordinator.statusMessage
		case .failed, .cancelled:
			return coordinator.statusMessage
		default:
			return nil
		}
	}

	// MARK: - Lifecycle

	private func ensureCoordinator() async {
		guard coordinator == nil else { return }
		await restartCoordinator()
	}

	private func restartCoordinator() async {
		let userId = authSession.user?.id ?? KeychainStore.get(.userId) ?? ""
		guard !userId.isEmpty else {
			startFailedMessage = "Sign in to use Radar."
			coordinator?.stop()
			coordinator = nil
			return
		}
		let name = authSession.preferredDisplayName
		coordinator?.stop()
		let next = BumpCoordinator(
			userId: userId,
			displayName: name == "You" ? "" : name,
			friendsStore: friendsStore
		)
		coordinator = next
		await next.start()
	}
}

// MARK: - Consent sheet model

private enum ConsentDirection: Equatable {
	case outgoing
	case incoming
}

private struct ConsentPresentation: Identifiable, Equatable {
	var peerDisplayName: String
	var direction: ConsentDirection
	var details: BumpPeerDetails

	var id: String {
		switch direction {
		case .outgoing: "out.\(peerDisplayName)"
		case .incoming: "in.\(peerDisplayName)"
		}
	}
}

#if DEBUG
#Preview("Radar · Mock peers") {
	NearbyRadarPreviewHost()
}
#endif
