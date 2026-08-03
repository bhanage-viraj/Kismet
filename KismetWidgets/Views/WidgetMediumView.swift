import SwiftUI
import WidgetKit

/// systemMedium — friends-only “Nearby” list.
struct NearbyMediumView: View {
	@Environment(\.widgetRenderingMode) private var renderingMode

	let cards: [WidgetAppGroup.Card]
	var headline: String? = nil

	private let contentPadding: CGFloat = 12
	private let sectionSpacing: CGFloat = 6
	private let rowSpacing: CGFloat = 6
	private let avatarSize: CGFloat = 30

	var body: some View {
		VStack(alignment: .leading, spacing: sectionSpacing) {
			header

			if cards.isEmpty {
				Text("No one nearby")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				Spacer(minLength: 0)
			} else {
				VStack(spacing: rowSpacing) {
					ForEach(cards.prefix(3)) { card in
						FriendListRow(
							card: card,
							trailing: .statusDot,
							avatarSize: avatarSize,
							showsAvatarStatusDot: false,
							isCompact: true
						)
					}
				}
				Spacer(minLength: 0)
			}
		}
		.padding(contentPadding)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.containerBackground(for: .widget) {
			ContainerRelativeShape()
				.fill(.background)
		}
	}

	private var header: some View {
		HStack(alignment: .center, spacing: 8) {
			Text("Nearby")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(.primary)
				.lineLimit(1)

			Spacer(minLength: 4)

			Image(systemName: "person.2.fill")
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(PresenceStatusColor.free)
				.widgetAccentable()
				.frame(width: 22, height: 22)
				.background(PresenceStatusColor.softChipFill(for: renderingMode), in: Circle())
				.accessibilityLabel(headline ?? "Friends nearby")
		}
	}
}

#Preview(as: .systemMedium) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
