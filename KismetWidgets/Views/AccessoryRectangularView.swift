import SwiftUI
import WidgetKit

/// `.accessoryRectangular` — top free/nearby friend at a glance.
///
/// Real Lock Screen slot is ~172×76pt (wide + short). Keep to three lines:
/// name, status, distance — with a small leading avatar for identity.
struct FriendStatusRectangularView: View {
	let card: WidgetAppGroup.Card?

	private let avatarSize: CGFloat = 28

	var body: some View {
		Group {
			if let card {
				filled(card)
			} else {
				empty
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
	}

	private func filled(_ card: WidgetAppGroup.Card) -> some View {
		HStack(alignment: .center, spacing: 8) {
			PresenceAvatar(
				card: card,
				size: avatarSize,
				ringWidth: 1.75,
				ringGap: 1.25,
				ringTrackColor: Color(.systemBackground),
				showsStatusDot: false
			)

			VStack(alignment: .leading, spacing: 2) {
				Text(card.displayName)
					.font(.headline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)

				statusLine(for: card)

				HStack(spacing: 3) {
					Image(systemName: "location.north.line.fill")
						.font(.system(size: 9, weight: .semibold))
						.widgetAccentable()
					Text(card.distanceText)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				.font(.caption2)
				.foregroundStyle(.secondary)
			}

			Spacer(minLength: 0)
		}
	}

	/// “Free” / “Working” stays accented; “until 4:30 PM” stays secondary — one line.
	@ViewBuilder
	private func statusLine(for card: WidgetAppGroup.Card) -> some View {
		let title = card.accessoryStatusTitle
		let detail = card.accessoryStatusDetail

		HStack(spacing: 4) {
			Text(title)
				.fontWeight(.semibold)
				.foregroundStyle(PresenceStatusColor.status(card.status))
				.widgetAccentable()

			if let detail, !detail.isEmpty {
				Text(detail)
					.foregroundStyle(.secondary)
			}
		}
		.font(.caption)
		.lineLimit(1)
		.minimumScaleFactor(0.85)
	}

	private var empty: some View {
		HStack(spacing: 8) {
			Image(systemName: "person.2")
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(.secondary)
				.widgetAccentable()
				.frame(width: avatarSize, height: avatarSize)

			VStack(alignment: .leading, spacing: 2) {
				Text("No one nearby")
					.font(.headline.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)
				Text("Open Kismet for live suggestions")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(2)
					.minimumScaleFactor(0.85)
			}

			Spacer(minLength: 0)
		}
	}
}

typealias AccessoryRectangularView = FriendStatusRectangularView

private extension WidgetAppGroup.Card {
	/// Accented status word — readable even when Lock Screen strips hue.
	var accessoryStatusTitle: String {
		switch status {
		case .free: "Free"
		case .busy: "Working"
		case .nearby: "Nearby"
		}
	}

	/// Rest of the status on the same line — e.g. “until 4:30 PM”.
	var accessoryStatusDetail: String? {
		let source = (freeUntilText?.isEmpty == false ? freeUntilText : statusLabel) ?? ""
		if let range = source.range(of: #"until\s+.+"#, options: [.regularExpression, .caseInsensitive]) {
			return String(source[range])
		}
		let stripped = source
			.replacingOccurrences(of: accessoryStatusTitle, with: "", options: .caseInsensitive)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		if stripped.isEmpty { return nil }
		// Drop a leading separator if we stripped a prefix word (“Working nearby” → “nearby”).
		return stripped
	}
}

#Preview(as: .accessoryRectangular) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
