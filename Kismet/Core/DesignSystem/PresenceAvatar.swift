import SwiftUI
import UIKit

/// Find My–style circular avatar used by widgets / Live Activities, adapted for the main app
/// (no WidgetKit dependency). Photo → background gap → status ring → optional presence dot.
struct PresenceAvatar: View {
	enum Status: Equatable, Sendable {
		case available
		case friendsOnly
		case busy
		case approximate
		case offline
		case you

		var color: Color {
			switch self {
			case .available: Color(red: 0.204, green: 0.780, blue: 0.349)
			case .friendsOnly: Color(red: 0.55, green: 0.40, blue: 0.92)
			case .busy: Color(red: 1.0, green: 0.624, blue: 0.110)
			case .approximate: Color(red: 0.90, green: 0.58, blue: 0.12)
			case .offline: Color(red: 0.55, green: 0.55, blue: 0.58)
			case .you: Color(red: 0.243, green: 0.557, blue: 0.969)
			}
		}

		init(_ presence: RadarPresence) {
			switch presence {
			case .available: self = .available
			case .friendsOnly: self = .friendsOnly
			case .approximate: self = .approximate
			case .eclipse: self = .offline
			}
		}
	}

	let initials: String
	let name: String
	var status: Status
	var size: CGFloat
	var ringWidth: CGFloat = 2.5
	var ringGap: CGFloat = 2.5
	var ringTrackColor: Color = Color(.systemBackground)
	var photo: UIImage? = nil
	var showsStatusDot: Bool = true
	var statusDotScale: CGFloat = 1.0
	var statusDotInset: CGFloat = 0
	var ringColor: Color? = nil

	private var statusColor: Color { ringColor ?? status.color }
	private var statusDotSize: CGFloat { max(11, size * 0.28 * statusDotScale) }
	private var statusDotStroke: CGFloat { max(1.75, statusDotSize * 0.2) }
	private var ringCenterlineRadius: CGFloat { (size - ringWidth) / 2 }

	private var statusDotOffset: CGSize {
		let angle = Angle.degrees(45)
		let radius = ringCenterlineRadius + statusDotInset
		return CGSize(
			width: CGFloat(Foundation.cos(angle.radians)) * radius,
			height: CGFloat(Foundation.sin(angle.radians)) * radius
		)
	}

	private var photoSize: CGFloat {
		max(1, size - (ringWidth * 2) - (ringGap * 2))
	}

	var body: some View {
		ZStack {
			Circle()
				.fill(ringTrackColor)
				.frame(width: size - ringWidth * 2, height: size - ringWidth * 2)

			avatarContent
				.frame(width: photoSize, height: photoSize)
				.clipShape(Circle())

			Circle()
				.strokeBorder(statusColor, lineWidth: ringWidth)
				.frame(width: size, height: size)

			if showsStatusDot {
				Circle()
					.fill(statusColor)
					.overlay {
						Circle()
							.strokeBorder(ringTrackColor, lineWidth: statusDotStroke)
					}
					.frame(width: statusDotSize, height: statusDotSize)
					.offset(x: statusDotOffset.width, y: statusDotOffset.height)
			}
		}
		.frame(width: size, height: size)
		.accessibilityLabel(name)
	}

	@ViewBuilder
	private var avatarContent: some View {
		if let photo {
			Image(uiImage: photo)
				.resizable()
				.scaledToFill()
		} else {
			ZStack {
				Circle()
					.fill(
						LinearGradient(
							colors: Self.avatarGradient(for: name),
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						)
					)
				Text(initials)
					.font(.system(size: photoSize * 0.36, weight: .semibold, design: .rounded))
					.foregroundStyle(.white)
			}
		}
	}

	static func initials(from name: String) -> String {
		let parts = name.split(separator: " ").prefix(2)
		let letters = parts.compactMap { $0.first.map(String.init) }
		if letters.isEmpty {
			return String(name.prefix(1)).uppercased()
		}
		return letters.joined().uppercased()
	}

	static func avatarGradient(for name: String) -> [Color] {
		let palette: [[Color]] = [
			[Color(red: 0.95, green: 0.75, blue: 0.55), Color(red: 0.85, green: 0.45, blue: 0.35)],
			[Color(red: 0.55, green: 0.70, blue: 0.95), Color(red: 0.35, green: 0.45, blue: 0.85)],
			[Color(red: 0.70, green: 0.85, blue: 0.55), Color(red: 0.35, green: 0.65, blue: 0.45)],
			[Color(red: 0.90, green: 0.60, blue: 0.75), Color(red: 0.70, green: 0.35, blue: 0.55)],
		]
		let index = abs(name.hashValue) % palette.count
		return palette[index]
	}

	static func photo(forUserId userId: String?) -> UIImage? {
		guard let userId, !userId.isEmpty else { return nil }
		return AppGroup.loadAvatarImage(friendID: userId)
	}
}

/// Stacked You + peer avatars — same idea as Live Activity `OverlappingAvatarCluster`.
struct OverlappingPresenceCluster: View {
	var selfName: String = "You"
	var selfPhoto: UIImage? = nil
	var peerName: String
	var peerPhoto: UIImage? = nil
	var peerStatus: PresenceAvatar.Status = .available
	var size: CGFloat = 72
	var overlap: CGFloat = 28

	var body: some View {
		HStack(spacing: -overlap) {
			PresenceAvatar(
				initials: PresenceAvatar.initials(from: selfName),
				name: selfName,
				status: .you,
				size: size,
				ringWidth: 2.5,
				ringGap: 2,
				ringTrackColor: Color(.systemBackground),
				photo: selfPhoto,
				showsStatusDot: false,
				ringColor: PresenceAvatar.Status.you.color
			)
			.overlay {
				Circle()
					.strokeBorder(Color(.systemBackground), lineWidth: 2)
			}
			.zIndex(0)

			PresenceAvatar(
				initials: PresenceAvatar.initials(from: peerName),
				name: peerName,
				status: peerStatus,
				size: size,
				ringWidth: 2.5,
				ringGap: 2,
				ringTrackColor: Color(.systemBackground),
				photo: peerPhoto,
				showsStatusDot: true
			)
			.overlay {
				Circle()
					.strokeBorder(Color(.systemBackground), lineWidth: 2)
			}
			.zIndex(1)
		}
	}
}
