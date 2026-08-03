import SwiftUI
import UIKit
import WidgetKit

/// systemMedium Friends Map — wide edge-to-edge map + slim footer chip.
struct FriendsMapMediumView: View {
	@Environment(\.widgetRenderingMode) private var renderingMode

	let snapshot: WidgetAppGroup.SuggestionSnapshot?
	var mapImage: UIImage? = nil

	private var cards: [WidgetAppGroup.Card] { snapshot?.cards ?? [] }
	private var friendCount: Int {
		snapshot?.friendCountNearby ?? cards.count
	}

	private var resolvedMapImage: UIImage? {
		// Only trust the timeline entry — never pull a stale pin-filled cache here.
		mapImage
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			Color.clear

			overlayCard
				.padding(.horizontal, 10)
				.padding(.bottom, 10)
		}
		.containerBackground(for: .widget) {
			mapBackground
		}
		.widgetURL(WidgetDeepLink.home)
	}

	@ViewBuilder
	private var mapBackground: some View {
		if let resolvedMapImage {
			Image(uiImage: resolvedMapImage)
				.resizable()
				.widgetAccentedRenderingMode(.accentedDesaturated)
				.scaledToFill()
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.clipped()
		} else {
			ZStack {
				Color(UIColor.secondarySystemFill)
				HStack(spacing: 8) {
					Image(systemName: "map.fill")
						.foregroundStyle(.secondary)
					Text("Open Kismet to load the map")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	private var overlayCard: some View {
		Link(destination: WidgetDeepLink.home) {
			HStack(spacing: 8) {
				Image(systemName: "person.2.fill")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(PresenceStatusColor.free)
					.widgetAccentable()
					.frame(width: 24, height: 24)
					.background(PresenceStatusColor.softChipFill(for: renderingMode), in: Circle())

				Text(friendsTitle)
					.font(.caption.weight(.bold))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)

				if !cards.isEmpty {
					Text("· Perfect time to meet!")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				}

				Spacer(minLength: 4)

				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 7)
			.background {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(.ultraThinMaterial)
					.overlay {
						if renderingMode.isAccented {
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(PresenceStatusColor.mapOverlayFill(for: renderingMode))
						}
					}
			}
		}
	}

	private var friendsTitle: String {
		if friendCount <= 0 { return "No friends nearby" }
		if friendCount == 1 { return "1 friend nearby" }
		return "\(friendCount) friends nearby"
	}
}

#Preview("Friends Map Medium", as: .systemMedium) {
	FriendsMapLargeWidget()
} timeline: {
	FriendAvailabilityEntry(date: .now, snapshot: WidgetPreviewData.emptySnapshot)
}
