import SwiftUI
import UIKit
import WidgetKit

/// Circular friend avatar with Find My–style ring:
/// photo → background-colored gap → mint status ring → optional presence dot.
struct PresenceAvatar: View {
	@Environment(\.widgetRenderingMode) private var renderingMode

	let initials: String
	let name: String
	var status: WidgetAppGroup.WidgetStatus
	var size: CGFloat
	var ringWidth: CGFloat = 2.5
	/// Empty track between photo and mint ring (filled with card background).
	var ringGap: CGFloat = 2.5
	/// Matches the widget card so the gap reads as “empty,” not another color.
	var ringTrackColor: Color = Color(.systemBackground)
	var photo: UIImage? = nil
	var showsStatusDot: Bool = true
	var statusDotScale: CGFloat = 1.0
	var statusDotInset: CGFloat = 0
	var ringColor: Color? = nil

	private var statusColor: Color { ringColor ?? PresenceStatusColor.status(status) }
	/// Find My–style presence badge — larger default so it reads on the mint ring.
	private var statusDotSize: CGFloat { max(11, size * 0.28 * statusDotScale) }
	private var statusDotStroke: CGFloat { max(1.75, statusDotSize * 0.2) }

	/// Centerline of the mint stroke (`strokeBorder` is drawn inside the circle).
	private var ringCenterlineRadius: CGFloat { (size - ringWidth) / 2 }

	/// Places the dot’s center on the mint ring at bottom-trailing (45°).
	/// `statusDotInset` nudges radially (positive = slightly outside the centerline).
	private var statusDotOffset: CGSize {
		let angle = Angle.degrees(45)
		let radius = ringCenterlineRadius + statusDotInset
		return CGSize(
			width: CGFloat(Foundation.cos(angle.radians)) * radius,
			height: CGFloat(Foundation.sin(angle.radians)) * radius
		)
	}

	/// Photo diameter = outer size minus mint stroke minus gap on both sides.
	private var photoSize: CGFloat {
		max(1, size - (ringWidth * 2) - (ringGap * 2))
	}

	var body: some View {
		ZStack {
			// 1. Background disc — becomes the visible empty ring between photo and mint.
			Circle()
				.fill(ringTrackColor)
				.frame(width: size - ringWidth * 2, height: size - ringWidth * 2)

			// 2. Avatar photo / initials.
			avatarContent
				.frame(width: photoSize, height: photoSize)
				.clipShape(Circle())

			// 3. Mint status ring on the outside.
			Circle()
				.strokeBorder(statusColor, lineWidth: ringWidth)
				.frame(width: size, height: size)
				.widgetAccentable()

			// 4. Online indicator centered on the mint ring, outlined in card background.
			if showsStatusDot {
				Circle()
					.fill(statusColor)
					.overlay {
						Circle()
							.strokeBorder(ringTrackColor, lineWidth: statusDotStroke)
					}
					.frame(width: statusDotSize, height: statusDotSize)
					.offset(x: statusDotOffset.width, y: statusDotOffset.height)
					.widgetAccentable()
			}
		}
		.frame(width: size, height: size)
	}

	@ViewBuilder
	private var avatarContent: some View {
		if let photo {
			Image(uiImage: photo)
				.resizable()
				.widgetAccentedRenderingMode(.accentedDesaturated)
				.scaledToFill()
		} else {
			ZStack {
				Circle()
					.fill(
						LinearGradient(
							colors: PresenceStatusColor.avatarGradient(for: name, mode: renderingMode),
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
}

extension PresenceAvatar {
	init(
		card: WidgetAppGroup.Card,
		size: CGFloat,
		ringWidth: CGFloat = 2.5,
		ringGap: CGFloat = 2.5,
		ringTrackColor: Color = Color(.systemBackground),
		showsStatusDot: Bool = true,
		statusDotScale: CGFloat = 1.0,
		statusDotInset: CGFloat = 0
	) {
		self.init(
			initials: card.initials,
			name: card.displayName,
			status: card.status,
			size: size,
			ringWidth: ringWidth,
			ringGap: ringGap,
			ringTrackColor: ringTrackColor,
			photo: WidgetAppGroup.loadAvatarImage(fileName: card.avatarFileName),
			showsStatusDot: showsStatusDot,
			statusDotScale: statusDotScale,
			statusDotInset: statusDotInset
		)
	}
}
