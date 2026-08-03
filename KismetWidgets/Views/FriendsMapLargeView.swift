import MapKit
import SwiftUI
import UIKit
import WidgetKit

/// systemLarge-only Friends Map — edge-to-edge MapKit snapshot.
struct FriendsMapLargeView: View {
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
				.padding(.horizontal, 12)
				.padding(.bottom, 12)
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
				VStack(spacing: 6) {
					Image(systemName: "map.fill")
						.font(.title3)
						.foregroundStyle(.secondary)
					Text("Open Kismet to load the map")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				.padding(12)
			}
		}
	}

	private var overlayCard: some View {
		Link(destination: WidgetDeepLink.home) {
			HStack(spacing: 8) {
				Image(systemName: "person.2.fill")
					.font(.caption.weight(.semibold))
					.foregroundStyle(PresenceStatusColor.free)
					.widgetAccentable()
					.frame(width: 28, height: 28)
					.background(PresenceStatusColor.softChipFill(for: renderingMode), in: Circle())

				VStack(alignment: .leading, spacing: 1) {
					Text(friendsTitle)
						.font(.caption.weight(.bold))
						.foregroundStyle(.primary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
					Text(cards.isEmpty ? "Check back soon" : "Perfect time to meet!")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}

				Spacer(minLength: 4)

				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.tertiary)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.background {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(.ultraThinMaterial)
					.overlay {
						if renderingMode.isAccented {
							RoundedRectangle(cornerRadius: 12, style: .continuous)
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

#Preview("Friends Map Large", as: .systemLarge) {
	FriendsMapLargeWidget()
} timeline: {
	FriendAvailabilityEntry(date: .now, snapshot: WidgetPreviewData.emptySnapshot)
}
