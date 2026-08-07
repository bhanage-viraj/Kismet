import SwiftUI
import WidgetKit

/// systemMedium — suggested meetup / event card.
struct MeetupMediumView: View {
	@Environment(\.widgetRenderingMode) private var renderingMode

	let meetup: WidgetAppGroup.FeaturedMeetup?
	var participants: [WidgetAppGroup.Card] = []
	var headline: String? = nil

	var body: some View {
		Group {
			if let meetup {
				filled(meetup)
			} else {
				empty
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.containerBackground(for: .widget) {
			ContainerRelativeShape()
				.fill(.background)
		}
		.widgetURL(WidgetDeepLink.meetup)
	}

	private func filled(_ meetup: WidgetAppGroup.FeaturedMeetup) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .center, spacing: 8) {
				Text("Suggested")
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(.primary)
					.lineLimit(1)

				Spacer(minLength: 4)

				Image(systemName: "calendar")
					.font(.system(size: 10, weight: .semibold))
					.foregroundStyle(PresenceStatusColor.free)
					.widgetAccentable()
					.frame(width: 22, height: 22)
					.background(PresenceStatusColor.softChipFill(for: renderingMode), in: Circle())
			}

			HStack(alignment: .center, spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.fill(PresenceStatusColor.softChipFill(for: renderingMode))
						.frame(width: 44, height: 44)
					Image(systemName: meetup.systemImage)
						.font(.title3.weight(.semibold))
						.foregroundStyle(PresenceStatusColor.free)
						.widgetAccentable()
				}

				VStack(alignment: .leading, spacing: 3) {
					Text(meetup.title)
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.primary)
						.lineLimit(1)
						.minimumScaleFactor(0.85)

					if let when = meetup.whenText, !when.isEmpty {
						Text(when)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}

					Text(metaLine(meetup))
						.font(.caption2.weight(.medium))
						.foregroundStyle(PresenceStatusColor.free)
						.lineLimit(1)
						.minimumScaleFactor(0.85)
						.widgetAccentable()
				}

				Spacer(minLength: 4)

				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.tertiary)
			}

			if !participants.isEmpty {
				Divider().opacity(0.3)

				HStack(spacing: -8) {
					ForEach(participants.prefix(3)) { card in
						PresenceAvatar(
							card: card,
							size: 26,
							ringWidth: 1.75,
							ringGap: 1.25,
							ringTrackColor: Color(.systemBackground),
							showsStatusDot: false
						)
						.overlay {
							Circle()
								.strokeBorder(Color(.systemBackground), lineWidth: 1.5)
						}
					}

					if let venue = meetup.venueName, !venue.isEmpty {
						Text(venue)
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(1)
							.padding(.leading, 14)
					}

					Spacer(minLength: 0)
				}
			} else if let venue = meetup.venueName, !venue.isEmpty {
				HStack(spacing: 4) {
					Image(systemName: "mappin.and.ellipse")
						.font(.caption2)
					Text(venue)
						.font(.caption2)
						.lineLimit(1)
				}
				.foregroundStyle(.secondary)
			}

			Spacer(minLength: 0)
		}
	}

	private var empty: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Suggested")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(.primary)
			Text("No meetup right now")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
			Text("Open Who's Out when friends are free nearby")
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(2)
			Spacer(minLength: 0)
		}
	}

	private func metaLine(_ meetup: WidgetAppGroup.FeaturedMeetup) -> String {
		var parts: [String] = []
		if let eta = meetup.etaText {
			parts.append("ETA \(eta)")
		}
		if let distance = meetup.distanceText {
			parts.append(distance.replacingOccurrences(of: " away", with: ""))
		}
		return parts.joined(separator: " · ")
	}
}

#Preview(as: .systemMedium) {
	SuggestedMeetupWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
