import SwiftUI
import UIKit
import WidgetKit

/// Friends Map — Medium + Large (no Extra Large).
struct FriendsMapLargeWidget: Widget {
	let kind = WidgetAppGroup.mapWidgetKind

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: NearbyMapProvider()) { entry in
			FriendsMapWidgetView(entry: entry)
		}
		.configurationDisplayName("Friends Map")
		.description("Nearby friends on a map.")
		.supportedFamilies([
			.systemMedium,
			.systemLarge,
		])
		.contentMarginsDisabled()
		// Map *is* the content — don’t let tinted/clear Home Screen strip it.
		.containerBackgroundRemovable(false)
	}
}

struct FriendsMapWidgetView: View {
	@Environment(\.widgetFamily) private var family
	var entry: FriendAvailabilityEntry

	var body: some View {
		switch family {
		case .systemMedium:
			FriendsMapMediumView(snapshot: entry.snapshot, mapImage: entry.mapImage)
		default:
			FriendsMapLargeView(snapshot: entry.snapshot, mapImage: entry.mapImage)
		}
	}
}
