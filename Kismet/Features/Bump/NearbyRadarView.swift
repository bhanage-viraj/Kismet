import SwiftUI
import UIKit

enum RadarPresence: String, CaseIterable, Sendable {
	case available
	case friendsOnly
	case approximate
	case eclipse
}

struct RadarFriend: Identifiable {
	var id: String
	var name: String
	var distanceMeters: Double
	/// Bearing in radians; same convention as `PolarPosition` (0 = +X, −π/2 = up).
	var bearingRadians: Double
	var presence: RadarPresence
	var photo: UIImage?
	var userId: String?

	init(
		id: String = UUID().uuidString,
		name: String,
		distanceMeters: Double,
		bearingRadians: Double,
		presence: RadarPresence,
		photo: UIImage? = nil,
		userId: String? = nil
	) {
		self.id = id
		self.name = name
		self.distanceMeters = distanceMeters
		self.bearingRadians = bearingRadians
		self.presence = presence
		self.photo = photo
		self.userId = userId
	}
}

/// Radar canvas for the Radar tab. App chrome (nav + tab bar) lives outside this view.
/// Peer markers are glow avatars (Option A); name shows only while selected.
struct NearbyRadarView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	var friends: [RadarFriend]
	var selectedFriendId: String?
	/// Rotating sweep + pulse rings while Multipeer is looking for peers.
	var isSearching: Bool = false
	var onSelectFriend: ((RadarFriend) -> Void)?

	private var animateSearch: Bool {
		isSearching && !reduceMotion
	}

	var body: some View {
		ZStack {
			KismetTheme.Bump.background(for: .nearby, scheme: colorScheme)

			radarCanvas
				.frame(maxHeight: .infinity)
				.padding(.horizontal, 8)
				.padding(.vertical, 12)
		}
	}

	// MARK: - Radar

	private var radarCanvas: some View {
		Group {
			if animateSearch {
				SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
					radarContent(at: timeline.date, sweeping: true)
				}
			} else {
				radarContent(at: .now, sweeping: false)
			}
		}
	}

	private func radarContent(at date: Date, sweeping: Bool) -> some View {
		let sweepAngle = sweeping ? Self.sweepAngle(at: date) : -.pi / 2
		let pulseProgress = sweeping ? Self.pulseProgress(at: date) : 0.0

		return GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height * 0.98)
			let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
			let outerRadius = side * 0.42
			let maxRange = KismetTheme.Bump.maxRadarRangeMeters

			ZStack {
				ForEach(Array(KismetTheme.Bump.ringRangesMeters.enumerated()), id: \.offset) { _, meters in
					let fraction = meters / maxRange
					let diameter = outerRadius * 2 * fraction
					Circle()
						.stroke(KismetTheme.Bump.ringStroke(for: colorScheme), lineWidth: 1)
						.frame(width: diameter, height: diameter)
						.position(center)
						.allowsHitTesting(false)
				}

				if isSearching {
					searchingPulses(
						center: center,
						outerRadius: outerRadius,
						progress: pulseProgress
					)
					.allowsHitTesting(false)
				}

				sweepWedge(radius: outerRadius)
					.frame(width: outerRadius * 2, height: outerRadius * 2)
					.rotationEffect(.radians(sweepAngle))
					.position(center)
					.allowsHitTesting(false)
					.opacity(isSearching ? 1 : 0.55)

				Circle()
					.fill(KismetTheme.Bump.youDot(for: colorScheme))
					.frame(width: 12, height: 12)
					.shadow(
						color: KismetTheme.Bump.youDot(for: colorScheme)
							.opacity(colorScheme == .light ? 0.28 : 0.45),
						radius: colorScheme == .light ? 8 : 6
					)
					.position(center)
					.accessibilityLabel("You")
					.allowsHitTesting(false)

				ForEach(friends) { friend in
					let point = PolarPosition.point(
						distance: CGFloat(friend.distanceMeters),
						maxRange: maxRange,
						center: center,
						outerRadius: outerRadius,
						angle: CGFloat(friend.bearingRadians)
					)
					friendBlip(friend, selected: friend.id == selectedFriendId)
						.position(point)
				}
			}
			.frame(width: geo.size.width, height: geo.size.height)
			.accessibilityLabel(isSearching ? "Radar searching for nearby people" : "Radar")
		}
		.aspectRatio(1, contentMode: .fit)
		.frame(maxWidth: .infinity)
	}

	@ViewBuilder
	private func searchingPulses(
		center: CGPoint,
		outerRadius: CGFloat,
		progress: Double
	) -> some View {
		ForEach(0..<2, id: \.self) { index in
			let staggered = (progress + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
			let scale = 0.25 + staggered * 0.8
			let opacity = (1 - staggered) * 0.55

			Circle()
				.stroke(
					KismetTheme.Bump.pulseStroke(for: colorScheme),
					lineWidth: 1.5
				)
				.frame(width: outerRadius * 2, height: outerRadius * 2)
				.scaleEffect(scale)
				.opacity(opacity)
				.position(center)
		}
	}

	private func sweepWedge(radius: CGFloat) -> some View {
		let half = KismetTheme.Bump.sweepConeDegrees * .pi / 180 / 2
		let center = CGPoint(x: radius, y: radius)
		return Path { path in
			path.move(to: center)
			path.addArc(
				center: center,
				radius: radius,
				startAngle: .radians(-half),
				endAngle: .radians(half),
				clockwise: false
			)
			path.closeSubpath()
		}
		.fill(
			AngularGradient(
				colors: [
					KismetTheme.Bump.sweepFill(for: colorScheme).opacity(0.02),
					KismetTheme.Bump.sweepFill(for: colorScheme),
					KismetTheme.Bump.sweepFill(for: colorScheme).opacity(0.02),
				],
				center: .center,
				angle: .degrees(0)
			)
		)
	}

	/// Full rotation every 3.2s.
	private static func sweepAngle(at date: Date) -> Double {
		let period = 3.2
		let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
		return t * .pi * 2
	}

	/// Expanding pulse cycle every 2.4s.
	private static func pulseProgress(at date: Date) -> Double {
		let period = 2.4
		return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
	}

	private func friendBlip(_ friend: RadarFriend, selected: Bool) -> some View {
		let size = KismetTheme.Bump.radarBlipAvatarSize
		let status = PresenceAvatar.Status(friend.presence)
		let photo = friend.photo ?? PresenceAvatar.photo(forUserId: friend.userId)

		return Button {
			onSelectFriend?(friend)
		} label: {
			VStack(spacing: 6) {
				ZStack {
					Circle()
						.fill(status.color.opacity(colorScheme == .light ? 0.16 : 0.28))
						.blur(radius: selected ? (colorScheme == .light ? 10 : 12) : 8)
						.frame(width: size + 16, height: size + 16)
						.opacity(selected ? 1 : 0.7)

					PresenceAvatar(
						initials: PresenceAvatar.initials(from: friend.name),
						name: friend.name,
						status: status,
						size: size,
						ringWidth: selected ? 3 : 2.5,
						ringGap: 2,
						ringTrackColor: KismetTheme.Bump.base(for: colorScheme),
						photo: photo,
						showsStatusDot: true
					)
					.shadow(
						color: colorScheme == .light
							? Color.black.opacity(selected ? 0.10 : 0.06)
							: status.color.opacity(0.35),
						radius: selected ? 10 : 6,
						y: colorScheme == .light ? 2 : 0
					)
				}

				if selected {
					Text(friend.name)
						.font(.caption.weight(.semibold))
						.foregroundStyle(KismetTheme.Bump.headline(for: colorScheme))
						.lineLimit(1)
						.padding(.horizontal, 8)
						.padding(.vertical, 3)
						.background {
							if colorScheme == .light {
								Capsule().fill(.ultraThinMaterial)
							} else {
								Capsule().fill(KismetTheme.Bump.blipBacking(for: colorScheme))
							}
						}
						.overlay {
							Capsule()
								.stroke(
									colorScheme == .light
										? Color.black.opacity(0.06)
										: KismetTheme.Bump.chromeBorder(for: colorScheme),
									lineWidth: colorScheme == .light ? 0.5 : 1
								)
						}
						.shadow(
							color: colorScheme == .light ? Color.black.opacity(0.06) : .clear,
							radius: 4,
							y: 1
						)
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(friend.name)
		.accessibilityHint("Opens Bump request")
		.accessibilityAddTraits(selected ? .isSelected : [])
	}
}

// MARK: - Preview data (Xcode Canvas only)

enum NearbyRadarPreviewData {
	static let friends: [RadarFriend] = [
		RadarFriend(
			id: "arjun",
			name: "Arjun",
			distanceMeters: 120,
			bearingRadians: -2.4,
			presence: .available,
			userId: "usr_arjun_preview"
		),
		RadarFriend(
			id: "diya",
			name: "Diya",
			distanceMeters: 280,
			bearingRadians: -0.55,
			presence: .friendsOnly,
			userId: "usr_diya_preview"
		),
		RadarFriend(
			id: "karthik",
			name: "Karthik",
			distanceMeters: 200,
			bearingRadians: -2.9,
			presence: .available,
			userId: "usr_karthik_preview"
		),
		RadarFriend(
			id: "meera",
			name: "Meera",
			distanceMeters: 360,
			bearingRadians: 0.55,
			presence: .approximate,
			userId: "usr_meera_preview"
		),
		RadarFriend(
			id: "rohan",
			name: "Rohan",
			distanceMeters: 450,
			bearingRadians: 1.55,
			presence: .eclipse,
			userId: "usr_rohan_preview"
		),
	]

	static let consentNew = BumpPeerDetails(
		displayName: "Arjun",
		userId: "usr_arjun_preview",
		distanceMeters: 2.0,
		alreadyFriends: false,
		connectedVia: nil,
		since: nil,
		hasPublicKey: false,
		keyVersion: nil,
		status: nil
	)

	static let consentFriend = BumpPeerDetails(
		displayName: "Diya",
		userId: "usr_diya_preview",
		distanceMeters: 1.4,
		alreadyFriends: true,
		connectedVia: "BUMP",
		since: Date().addingTimeInterval(-86400 * 28),
		hasPublicKey: true,
		keyVersion: 1,
		status: "ACTIVE"
	)

	static func details(for friend: RadarFriend) -> BumpPeerDetails {
		BumpPeerDetails(
			displayName: friend.name,
			userId: friend.userId,
			distanceMeters: friend.distanceMeters < 50
				? friend.distanceMeters
				: max(1, friend.distanceMeters / 80),
			alreadyFriends: friend.presence == .friendsOnly,
			connectedVia: friend.presence == .friendsOnly ? "INVITE_CODE" : nil,
			since: friend.presence == .friendsOnly
				? Date().addingTimeInterval(-86400 * 14)
				: nil,
			hasPublicKey: friend.presence == .friendsOnly,
			keyVersion: friend.presence == .friendsOnly ? 1 : nil,
			status: friend.presence == .friendsOnly ? "ACTIVE" : nil
		)
	}
}

#Preview("Nearby · Searching") {
	NavigationStack {
		NearbyRadarView(friends: [], isSearching: true)
			.navigationTitle("Radar")
			.navigationBarTitleDisplayMode(.inline)
	}
	.preferredColorScheme(.dark)
}

#Preview("Nearby · Peers + Searching") {
	NavigationStack {
		NearbyRadarView(
			friends: NearbyRadarPreviewData.friends,
			selectedFriendId: nil,
			isSearching: true
		)
		.navigationTitle("Radar")
		.navigationBarTitleDisplayMode(.inline)
	}
	.preferredColorScheme(.dark)
}

#Preview("Nearby · Selected · Dark") {
	NavigationStack {
		NearbyRadarView(
			friends: NearbyRadarPreviewData.friends,
			selectedFriendId: "arjun",
			isSearching: false
		)
		.navigationTitle("Radar")
		.navigationBarTitleDisplayMode(.inline)
	}
	.preferredColorScheme(.dark)
}

#Preview("Nearby · Light · Searching") {
	NavigationStack {
		NearbyRadarView(
			friends: NearbyRadarPreviewData.friends,
			selectedFriendId: "arjun",
			isSearching: true
		)
		.navigationTitle("Radar")
		.navigationBarTitleDisplayMode(.inline)
	}
	.preferredColorScheme(.light)
}

#Preview("Nearby · Light") {
	NavigationStack {
		NearbyRadarView(
			friends: NearbyRadarPreviewData.friends,
			selectedFriendId: "meera",
			isSearching: false
		)
		.navigationTitle("Radar")
		.navigationBarTitleDisplayMode(.inline)
	}
	.preferredColorScheme(.light)
}

#Preview("Nearby · Interactive mock") {
	NearbyRadarPreviewHost()
}

/// Canvas-only host: tap a mock peer to open the consent sheet.
struct NearbyRadarPreviewHost: View {
	@State private var selectedId: String?
	@State private var consent: PreviewConsent?

	var body: some View {
		NavigationStack {
			NearbyRadarView(
				friends: NearbyRadarPreviewData.friends,
				selectedFriendId: selectedId,
				isSearching: true,
				onSelectFriend: { friend in
					selectedId = friend.id
					consent = PreviewConsent(details: NearbyRadarPreviewData.details(for: friend))
				}
			)
			.navigationTitle("Radar")
			.navigationBarTitleDisplayMode(.inline)
		}
		.preferredColorScheme(.dark)
		.sheet(item: $consent) { item in
			BumpConsentView(
				details: item.details,
				onAccept: { consent = nil },
				onDecline: { consent = nil }
			)
		}
	}

	private struct PreviewConsent: Identifiable {
		var id: String { details.userId ?? details.displayName }
		var details: BumpPeerDetails
	}
}

