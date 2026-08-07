import SwiftUI
import WidgetKit

/// systemLarge — “Your Social Day” friend list + suggested meetup.
struct SocialDayLargeView: View {
	let snapshot: WidgetAppGroup.SuggestionSnapshot?

	var body: some View {
		Group {
			if let snapshot, !snapshot.cards.isEmpty {
				filled(snapshot)
			} else {
				empty
			}
		}
		.containerBackground(for: .widget) {
			ContainerRelativeShape()
				.fill(.background)
		}
	}

	private func filled(_ snapshot: WidgetAppGroup.SuggestionSnapshot) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			header(headline: snapshot.headline)

			VStack(spacing: 10) {
				ForEach(snapshot.cards.prefix(2)) { card in
					FriendListRow(
						card: card,
						trailing: .distance,
						avatarSize: 36,
						showsAvatarStatusDot: true,
						isCompact: false
					)
				}
			}

			Spacer(minLength: 8)

			Divider()
				.opacity(0.3)

			if let meetup = snapshot.featuredMeetup {
				Link(destination: WidgetDeepLink.meetup) {
					MeetupRow(
						systemImage: "calendar",
						title: largeMeetupTitle(meetup),
						subtitle: meetup.whenText
							?? (meetup.etaText.map { "ETA \($0)" } ?? ""),
						label: "Suggested meetup",
						usesElevatedBackground: true
					)
				}
			}
		}
		.padding(16)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
	}

	private func header(headline: String) -> some View {
		HStack(alignment: .top, spacing: 8) {
			VStack(alignment: .leading, spacing: 3) {
				Text("Your Social Day")
					.font(.system(size: 17, weight: .bold))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.9)

				Text(headline.isEmpty ? "Friends nearby" : headline)
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(PresenceStatusColor.free)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
					.widgetAccentable()
			}

			Spacer(minLength: 8)

			Image(systemName: "sparkles")
				.font(.body.weight(.semibold))
				.foregroundStyle(PresenceStatusColor.free)
				.widgetAccentable()
				.accessibilityHidden(true)
		}
	}

	private func largeMeetupTitle(_ meetup: WidgetAppGroup.FeaturedMeetup) -> String {
		if let venue = meetup.venueName, !venue.isEmpty {
			if meetup.title.localizedCaseInsensitiveContains(venue) {
				return meetup.title
			}
			return "Coffee at \(venue)"
		}
		return meetup.title
	}

	private var empty: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Your Social Day")
				.font(.system(size: 17, weight: .bold))
				.foregroundStyle(.primary)
			Text("No friends free nearby")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(PresenceStatusColor.free)
				.widgetAccentable()
			Spacer(minLength: 0)
			Text("Open Who's Out when friends are around")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(16)
	}
}

#Preview(as: .systemLarge) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
