import SwiftUI

/// Snapshot of everything we know about a nearby peer at consent time.
/// Pre-friendship: Multipeer discovery (`uid`, `name`) + distance.
/// Already friends: enriched from `GET /friends` cache in `FriendsStore`.
struct BumpPeerDetails: Equatable, Sendable {
	var displayName: String
	var userId: String?
	var distanceMeters: Double?
	var alreadyFriends: Bool
	var connectedVia: String?
	var since: Date?
	var hasPublicKey: Bool
	var keyVersion: Int?
	var status: String?

	static func from(
		peer: BumpDiscoveredPeer,
		distanceMeters: Double?,
		friend: FriendSummaryDTO?
	) -> BumpPeerDetails {
		let discoveryName = peer.discoveryInfo["name"]?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let name = [discoveryName, friend?.displayName, peer.peerIDDisplayName]
			.compactMap { $0 }
			.first { !$0.isEmpty } ?? peer.peerIDDisplayName

		return BumpPeerDetails(
			displayName: name,
			userId: peer.discoveryInfo["uid"] ?? friend?.userId,
			distanceMeters: distanceMeters,
			alreadyFriends: friend != nil,
			connectedVia: friend?.connectedVia,
			since: friend?.since,
			hasPublicKey: friend?.publicKey?.isEmpty == false,
			keyVersion: friend.map(\.keyVersion),
			status: friend?.status
		)
	}
}

/// Mutual-accept consent UI when a nearby Bump peer is selected.
struct BumpConsentView: View {
	@Environment(\.colorScheme) private var colorScheme

	var details: BumpPeerDetails
	var peerPhoto: UIImage?
	var selfPhoto: UIImage?
	var onAccept: () -> Void
	var onDecline: () -> Void

	private var peerName: String { details.displayName }
	private var resolvedPeerPhoto: UIImage? {
		peerPhoto ?? PresenceAvatar.photo(forUserId: details.userId)
	}

	var body: some View {
		ZStack {
			KismetTheme.Bump.background(for: .consent, scheme: colorScheme)

			VStack(spacing: 0) {
				header
					.padding(.horizontal, 20)
					.padding(.top, 8)

				Spacer(minLength: 16)

				avatarCluster
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(accessibilitySummary)

				VStack(spacing: 6) {
					Text("\(peerName) is nearby")
						.font(.title3.weight(.bold))
						.foregroundStyle(KismetTheme.Bump.headline(for: colorScheme))
					if let distanceLabel {
						Text("~\(distanceLabel) away")
							.font(.subheadline)
							.foregroundStyle(KismetTheme.Bump.secondaryText(for: colorScheme))
					}
				}
				.padding(.top, 24)
				.accessibilityElement(children: .combine)

				Spacer(minLength: 24)

				actionButtons
					.padding(.horizontal, 20)

				privacyFooter
					.padding(.top, 20)
					.padding(.bottom, 12)
			}
		}
	}

	// MARK: - Header

	private var header: some View {
		ZStack(alignment: .top) {
			VStack(spacing: 8) {
				Text("Bump")
					.font(.system(size: 28, weight: .bold))
					.foregroundStyle(KismetTheme.Bump.headline(for: colorScheme))
				Text("Find friends nearby.\nBoth of you must accept to connect.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundStyle(KismetTheme.Bump.secondaryText(for: colorScheme))
			}
			.frame(maxWidth: .infinity)
			.padding(.top, 4)

			HStack {
				chromeButton(systemName: "xmark", accessibilityLabel: "Dismiss") {
					onDecline()
				}
				Spacer()
			}
		}
	}

	// MARK: - Avatars (Live Activity–style overlapping PresenceAvatar)

	private var avatarCluster: some View {
		let size = KismetTheme.Bump.consentAvatarSize

		return ZStack {
			ForEach([0.55, 0.78, 1.0], id: \.self) { fraction in
				Circle()
					.stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
					.foregroundStyle(KismetTheme.Bump.violetStart.opacity(colorScheme == .dark ? 0.22 : 0.28))
					.frame(width: size * 2.4 * fraction, height: size * 2.4 * fraction)
			}

			OverlappingPresenceCluster(
				selfName: "You",
				selfPhoto: selfPhoto,
				peerName: peerName,
				peerPhoto: resolvedPeerPhoto,
				peerStatus: details.alreadyFriends ? .available : .approximate,
				size: size,
				overlap: size * 0.42
			)

			Image(systemName: "sparkle")
				.font(.system(size: 22, weight: .bold))
				.foregroundStyle(.white)
				.shadow(color: KismetTheme.Bump.violetEnd.opacity(0.9), radius: 8)
				.shadow(color: .white.opacity(0.8), radius: 2)
				.offset(y: -size * 0.12)
				.accessibilityHidden(true)
		}
		.frame(height: size * 2.2)
	}

	// MARK: - Actions

	private var actionButtons: some View {
		HStack(spacing: 12) {
			Button(action: onDecline) {
				Label("Not now", systemImage: "xmark")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.frame(height: KismetTheme.Bump.buttonHeight)
					.foregroundStyle(KismetTheme.Bump.headline(for: colorScheme))
					.background(
						KismetTheme.Bump.secondaryFill(for: colorScheme),
						in: RoundedRectangle(cornerRadius: KismetTheme.Bump.buttonCornerRadius, style: .continuous)
					)
					.overlay {
						RoundedRectangle(cornerRadius: KismetTheme.Bump.buttonCornerRadius, style: .continuous)
							.stroke(KismetTheme.Bump.chromeBorder(for: colorScheme), lineWidth: 1)
					}
			}
			.accessibilityLabel("Not now")

			Button(action: onAccept) {
				Label(details.alreadyFriends ? "Bump again" : "Accept", systemImage: "checkmark")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.frame(height: KismetTheme.Bump.buttonHeight)
					.foregroundStyle(.white)
					.background(
						KismetTheme.Bump.acceptGradient,
						in: RoundedRectangle(cornerRadius: KismetTheme.Bump.buttonCornerRadius, style: .continuous)
					)
			}
			.accessibilityLabel(details.alreadyFriends ? "Bump again" : "Accept bump")
		}
	}

	private var privacyFooter: some View {
		HStack(spacing: 6) {
			Image(systemName: "lock.fill")
				.font(.caption2)
			Text(
				details.alreadyFriends
					? "You’re already connected — Bump refreshes the link."
					: "Private. Only revealed after mutual accept."
			)
			.font(.caption)
		}
		.foregroundStyle(KismetTheme.Bump.secondaryText(for: colorScheme))
		.multilineTextAlignment(.center)
		.accessibilityElement(children: .combine)
	}

	private func chromeButton(
		systemName: String,
		accessibilityLabel: String,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(KismetTheme.Bump.headline(for: colorScheme))
				.frame(
					width: KismetTheme.Bump.chromeButtonSize,
					height: KismetTheme.Bump.chromeButtonSize
				)
				.background(
					KismetTheme.Bump.secondaryFill(for: colorScheme),
					in: Circle()
				)
				.overlay {
					Circle()
						.stroke(KismetTheme.Bump.chromeBorder(for: colorScheme), lineWidth: 1)
				}
		}
		.accessibilityLabel(accessibilityLabel)
	}

	// MARK: - Formatting

	private var distanceLabel: String? {
		guard let meters = details.distanceMeters else { return nil }
		if meters < 1 {
			return String(format: "%.0f cm", meters * 100)
		}
		if meters < 10 {
			return String(format: "%.0f m", meters)
		}
		return String(format: "%.0f m", meters)
	}

	private var accessibilitySummary: String {
		var parts = ["\(peerName) nearby"]
		if let distanceLabel { parts.append("about \(distanceLabel)") }
		if details.alreadyFriends { parts.append("already friends") }
		return parts.joined(separator: ", ")
	}
}

#Preview("Bump consent · New · Dark") {
	BumpConsentView(
		details: NearbyRadarPreviewData.consentNew,
		onAccept: {},
		onDecline: {}
	)
	.preferredColorScheme(.dark)
}

#Preview("Bump consent · Friend · Light") {
	BumpConsentView(
		details: NearbyRadarPreviewData.consentFriend,
		onAccept: {},
		onDecline: {}
	)
	.preferredColorScheme(.light)
}
