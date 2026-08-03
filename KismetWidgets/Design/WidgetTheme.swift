import SwiftUI

/// Thin compatibility façade over `PresenceStatusColor` for views not yet migrated.
/// Prefer `PresenceStatusColor` / `PresenceAvatar` / `FriendListRow` in new code.
///
/// Accented / tinted Home Screen support lives on `PresenceStatusColor` +
/// `.widgetAccentable()` / `.widgetAccentedRenderingMode(_:)` on individual views.
enum WidgetTheme {
	static let accent = PresenceStatusColor.free
	static let busy = PresenceStatusColor.busy
	static let nearby = PresenceStatusColor.nearby

	static let title = PresenceStatusColor.title
	static let secondary = PresenceStatusColor.secondary
	static let tertiary = PresenceStatusColor.tertiary

	static let cardFill = PresenceStatusColor.cardFill
	static let subtleFill = PresenceStatusColor.subtleFill

	static func status(_ status: WidgetAppGroup.WidgetStatus) -> Color {
		PresenceStatusColor.status(status)
	}

	static func avatarGradient(for name: String) -> [Color] {
		PresenceStatusColor.avatarGradient(for: name)
	}
}

/// Backward-compatible alias — prefer `PresenceAvatar`.
typealias WidgetAvatarView = PresenceAvatar

/// Backward-compatible alias — prefer `StatusPresenceDot`.
typealias WidgetStatusDot = StatusPresenceDot

/// Backward-compatible wrapper around `FriendListRow`.
struct WidgetFriendRow: View {
	let card: WidgetAppGroup.Card
	var showDistance: Bool = false
	var avatarSize: CGFloat = 36

	var body: some View {
		FriendListRow(
			card: card,
			trailing: showDistance ? .distance : .none,
			avatarSize: avatarSize
		)
	}
}
