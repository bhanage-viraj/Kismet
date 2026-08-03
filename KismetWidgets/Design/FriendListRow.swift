import SwiftUI
import WidgetKit

/// Shared friend row for Medium (trailing status dot) and Large (status-tinted distance).
struct FriendListRow: View {
	enum TrailingStyle {
		case statusDot
		case distance
		case none
	}

	let card: WidgetAppGroup.Card
	var trailing: TrailingStyle = .none
	var avatarSize: CGFloat = 36
	/// When false, only the ring is shown — useful when a trailing status dot already conveys presence.
	var showsAvatarStatusDot: Bool = true
	var isCompact: Bool = false

	var body: some View {
		HStack(spacing: isCompact ? 8 : 10) {
			PresenceAvatar(
				card: card,
				size: avatarSize,
				ringWidth: isCompact ? 1.75 : 2,
				ringGap: isCompact ? 1.25 : 1.5,
				ringTrackColor: Color(.systemBackground),
				showsStatusDot: showsAvatarStatusDot,
				statusDotScale: 0.95,
				statusDotInset: 0
			)

			VStack(alignment: .leading, spacing: 1) {
				Text(card.displayName)
					.font(isCompact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
				Text(card.statusLabel)
					.font(isCompact ? .caption2 : .caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
			}

			Spacer(minLength: 4)

			switch trailing {
			case .statusDot:
				StatusPresenceDot(status: card.status, size: isCompact ? 7 : 8)
			case .distance:
				Text(shortDistance(card.distanceText))
					.font(isCompact ? .caption2.weight(.medium) : .caption.weight(.medium))
					.foregroundStyle(PresenceStatusColor.status(card.status))
					.lineLimit(1)
					.widgetAccentable()
			case .none:
				EmptyView()
			}
		}
	}

	private func shortDistance(_ text: String) -> String {
		text
			.replacingOccurrences(of: " away", with: "")
			.replacingOccurrences(of: "away", with: "")
			.trimmingCharacters(in: .whitespaces)
	}
}
