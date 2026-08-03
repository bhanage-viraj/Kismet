import SwiftUI
import WidgetKit

/// systemSmall — “Nearby Now” (Find My–style centering, no GeometryReader).
struct NearbyNowSmallView: View {
	let card: WidgetAppGroup.Card?

	@Environment(\.widgetFamily) private var family

	private var metrics: LayoutMetrics { LayoutMetrics(family: family) }

	var body: some View {
		Group {
			if let card {
				filled(card)
			} else {
				empty
			}
		}
		.containerBackground(for: .widget) {
			ContainerRelativeShape()
				.fill(.background)
		}
	}

	private func filled(_ card: WidgetAppGroup.Card) -> some View {
		// ZStack defaults to center — the reliable WidgetKit centering pattern.
		ZStack {
			VStack(spacing: metrics.stackSpacing) {
				Text("Nearby Now")
					.font(.caption2.weight(.medium))
					.foregroundStyle(PresenceStatusColor.free)
					.widgetAccentable()
					.lineLimit(1)

				PresenceAvatar(
					card: card,
					size: metrics.avatarSize,
					ringWidth: metrics.ringWidth,
					ringGap: metrics.ringGap,
					ringTrackColor: Color(.systemBackground),
					statusDotScale: 1.0,
					statusDotInset: 0
				)

				VStack(spacing: metrics.nameStatusSpacing) {
					Text(card.displayName)
						.font(metrics.nameFont)
						.foregroundStyle(.primary)
						.tracking(-0.3)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
						.layoutPriority(1)

					Text(card.statusLabel)
						.font(.caption2.weight(.regular))
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}

				HStack(spacing: 3) {
					Image(systemName: "location.north.line.fill")
						.font(.system(size: 9, weight: .semibold))
						.widgetAccentable()
					Text(card.distanceText)
						.font(.caption2.weight(.medium))
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				.foregroundStyle(.secondary)
			}
			.multilineTextAlignment(.center)
			.padding(.horizontal, metrics.horizontalPadding)
			.padding(.vertical, metrics.verticalPadding)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}

	private var empty: some View {
		ZStack {
			VStack(spacing: metrics.stackSpacing) {
				Text("Nearby Now")
					.font(.caption2.weight(.medium))
					.foregroundStyle(PresenceStatusColor.free)
					.widgetAccentable()
					.lineLimit(1)

				Text("No one nearby")
					.font(metrics.nameFont)
					.foregroundStyle(.primary)
					.tracking(-0.3)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
					.layoutPriority(1)

				Text("Open Kismet for live suggestions")
					.font(.caption2.weight(.regular))
					.foregroundStyle(.secondary)
					.lineLimit(2)
					.minimumScaleFactor(0.85)
					.multilineTextAlignment(.center)
			}
			.padding(.horizontal, metrics.horizontalPadding)
			.padding(.vertical, metrics.verticalPadding)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Layout metrics

private struct LayoutMetrics {
	let avatarSize: CGFloat
	let ringWidth: CGFloat
	let ringGap: CGFloat
	let verticalPadding: CGFloat
	let horizontalPadding: CGFloat
	let stackSpacing: CGFloat
	let nameStatusSpacing: CGFloat
	let nameFont: Font

	init(family: WidgetFamily) {
		switch family {
		case .systemSmall:
			verticalPadding = 10
			horizontalPadding = 12
			stackSpacing = 6
			nameStatusSpacing = 2
			ringWidth = 3
			ringGap = 3
			avatarSize = 50
			nameFont = .system(size: 16, weight: .bold)

		case .systemMedium:
			verticalPadding = 12
			horizontalPadding = 14
			stackSpacing = 10
			nameStatusSpacing = 3
			ringWidth = 3
			ringGap = 3
			avatarSize = 52
			nameFont = .system(size: 18, weight: .bold)

		default:
			verticalPadding = 10
			horizontalPadding = 12
			stackSpacing = 6
			nameStatusSpacing = 2
			ringWidth = 3
			ringGap = 3
			avatarSize = 50
			nameFont = .system(size: 16, weight: .bold)
		}
	}
}

#Preview(as: .systemSmall) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
