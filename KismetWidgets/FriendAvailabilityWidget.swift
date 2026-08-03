import SwiftUI
import WidgetKit

struct FriendAvailabilityEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetAppGroup.SuggestionSnapshot?
	var mapImage: UIImage? = nil
}

struct FriendAvailabilityProvider: TimelineProvider {
	func placeholder(in context: Context) -> FriendAvailabilityEntry {
		FriendAvailabilityEntry(date: .now, snapshot: WidgetPreviewData.emptySnapshot)
	}

	func getSnapshot(in context: Context, completion: @escaping (FriendAvailabilityEntry) -> Void) {
		completion(FriendAvailabilityEntry(date: .now, snapshot: WidgetAppGroup.loadSnapshot()))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<FriendAvailabilityEntry>) -> Void) {
		let snapshot = WidgetAppGroup.loadSnapshot()
		let entry = FriendAvailabilityEntry(date: .now, snapshot: snapshot)
		let nextRefresh: Date = {
			if let updatedAt = snapshot?.updatedAt {
				return min(updatedAt.addingTimeInterval(WidgetAppGroup.staleInterval), Date().addingTimeInterval(15 * 60))
			}
			return Date().addingTimeInterval(15 * 60)
		}()
		completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
	}
}

/// Timeline provider for Friends Map — prefers App Group MapKit images from the main app.
struct NearbyMapProvider: TimelineProvider {
	func placeholder(in context: Context) -> FriendAvailabilityEntry {
		FriendAvailabilityEntry(date: .now, snapshot: WidgetPreviewData.emptySnapshot)
	}

	func getSnapshot(in context: Context, completion: @escaping (FriendAvailabilityEntry) -> Void) {
		makeEntry(family: context.family, displaySize: context.displaySize, completion: completion)
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<FriendAvailabilityEntry>) -> Void) {
		makeEntry(family: context.family, displaySize: context.displaySize) { entry in
			let nextRefresh: Date = {
				if let updatedAt = entry.snapshot?.updatedAt {
					return min(updatedAt.addingTimeInterval(WidgetAppGroup.staleInterval), Date().addingTimeInterval(15 * 60))
				}
				return Date().addingTimeInterval(15 * 60)
			}()
			completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
		}
	}

	private func makeEntry(
		family: WidgetFamily,
		displaySize: CGSize,
		completion: @escaping (FriendAvailabilityEntry) -> Void
	) {
		let snapshot = WidgetAppGroup.loadSnapshot()
		let cards = snapshot?.cards ?? []

		// Never reuse a pin-filled map cache when there are no real friends.
		guard !cards.isEmpty else {
			WidgetAppGroup.clearCachedMapImage()
			completion(FriendAvailabilityEntry(date: .now, snapshot: snapshot, mapImage: nil))
			return
		}

		if let cached = WidgetAppGroup.loadCachedMapImage(for: family) {
			completion(FriendAvailabilityEntry(date: .now, snapshot: snapshot, mapImage: cached))
			return
		}

		renderMap(snapshot: snapshot, family: family, displaySize: displaySize) { image in
			completion(FriendAvailabilityEntry(date: .now, snapshot: snapshot, mapImage: image))
		}
	}

	private func renderMap(
		snapshot: WidgetAppGroup.SuggestionSnapshot?,
		family: WidgetFamily,
		displaySize: CGSize,
		completion: @escaping (UIImage?) -> Void
	) {
		let fallback: CGSize = family == .systemMedium
			? CGSize(width: 338, height: 169)
			: CGSize(width: 338, height: 354)
		let size = displaySize.width > 1 ? displaySize : fallback
		WidgetMapSnapshotBuilder.render(
			data: snapshot,
			size: size,
			traitCollection: UITraitCollection.current
		) { image in
			if let image {
				WidgetAppGroup.saveCachedMapImage(image, for: family)
			}
			completion(image)
		}
	}
}

struct FriendAvailabilityWidget: Widget {
	let kind = WidgetAppGroup.widgetKind

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: FriendAvailabilityProvider()) { entry in
			FriendAvailabilityWidgetView(entry: entry)
		}
		.configurationDisplayName("Nearby Friends")
		.description("See who's nearby and free right now.")
		.supportedFamilies([
			.systemSmall,
			.systemMedium,
			.systemLarge,
			.accessoryCircular,
			.accessoryRectangular,
			.accessoryInline,
		])
	}
}

struct FriendAvailabilityWidgetView: View {
	@Environment(\.widgetFamily) private var widgetFamily

	var entry: FriendAvailabilityEntry

	private var isAccessoryFamily: Bool {
		switch widgetFamily {
		case .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner:
			true
		default:
			false
		}
	}

	var body: some View {
		let snapshot = entry.snapshot
		let cards = snapshot?.cards ?? []
		let freeCount = cards.filter { $0.status == .free }.count
		let nearbyCount = max(snapshot?.friendCountNearby ?? 0, cards.count)
		let headline = snapshot?.headline ?? ""
		let topFree = cards.first(where: { $0.status == .free }) ?? cards.first

		Group {
			switch widgetFamily {
			case .systemMedium:
				NearbyMediumView(
					cards: cards,
					headline: headline
				)
			case .systemLarge:
				SocialDayLargeView(snapshot: snapshot)
			case .accessoryCircular:
				FriendsFreeCircularView(
					freeCount: freeCount,
					nearbyCount: nearbyCount
				)
			case .accessoryRectangular:
				FriendStatusRectangularView(card: topFree)
			case .accessoryInline:
				NearbyInlineView(
					nearbyCount: nearbyCount,
					freeCount: freeCount,
					fallbackHeadline: headline
				)
			case .accessoryCorner:
				FriendsBadgeCornerView(freeCount: freeCount > 0 ? freeCount : nearbyCount)
			default:
				NearbyNowSmallView(card: topFree)
			}
		}
		.widgetURL(defaultURL(for: topFree))
		.containerBackground(for: .widget) {
			if isAccessoryFamily {
				AccessoryWidgetBackground()
			} else {
				PresenceStatusColor.card
			}
		}
	}

	private func defaultURL(for card: WidgetAppGroup.Card?) -> URL {
		if let card {
			return WidgetDeepLink.friend(card.friendID)
		}
		return WidgetDeepLink.home
	}
}

// MARK: - Additional widgets (same provider / snapshot)

/// Medium-only widget focused on the suggested meetup / event.
struct SuggestedMeetupWidget: Widget {
	let kind = WidgetAppGroup.meetupWidgetKind

	var body: some WidgetConfiguration {
		StaticConfiguration(kind: kind, provider: FriendAvailabilityProvider()) { entry in
			MeetupMediumView(
				meetup: entry.snapshot?.featuredMeetup,
				participants: entry.snapshot?.cards ?? [],
				headline: entry.snapshot?.headline
			)
		}
		.configurationDisplayName("Suggested Meetup")
		.description("See your next coffee catch-up and who’s around.")
		.supportedFamilies([.systemMedium])
	}
}

#Preview(as: .systemSmall) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}

#Preview(as: .systemMedium) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}

#Preview(as: .systemLarge) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}

#Preview("Friends Map", as: .systemLarge) {
	FriendsMapLargeWidget()
} timeline: {
	FriendAvailabilityEntry(date: .now, snapshot: WidgetPreviewData.emptySnapshot)
}

#Preview(as: .accessoryCircular) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}

#Preview(as: .accessoryRectangular) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}

#Preview(as: .accessoryInline) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
}
