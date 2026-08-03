import SwiftUI
import WidgetKit

/// Green chip + title + subtitle + chevron — Medium footer, Large suggested meetup, ExtraLarge overlay.
struct MeetupRow: View {
	@Environment(\.widgetRenderingMode) private var renderingMode

	var systemImage: String
	var title: String
	var subtitle: String
	var label: String? = nil
	var usesElevatedBackground: Bool = true

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let label {
					Text(label)
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
					.textCase(.uppercase)
			}

			HStack(spacing: 10) {
				ZStack {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(PresenceStatusColor.softChipFill(for: renderingMode))
						.frame(width: 36, height: 36)
					Image(systemName: systemImage)
						.font(.body.weight(.semibold))
						.foregroundStyle(PresenceStatusColor.free)
						.widgetAccentable()
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.primary)
						.lineLimit(1)
					if !subtitle.isEmpty {
						Text(subtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}

				Spacer(minLength: 4)

				Image(systemName: "chevron.right")
					.font(.caption.weight(.semibold))
					.foregroundStyle(PresenceStatusColor.tertiary)
			}
		}
		.padding(usesElevatedBackground ? 12 : 0)
		.background {
			if usesElevatedBackground {
				RoundedRectangle(cornerRadius: 16, style: .continuous)
					.fill(PresenceStatusColor.elevatedFill(for: renderingMode))
			}
		}
	}
}

extension MeetupRow {
	init(meetup: WidgetAppGroup.FeaturedMeetup, label: String? = nil, titleOverride: String? = nil) {
		let title = titleOverride ?? meetup.title
		var parts: [String] = []
		if let eta = meetup.etaText {
			parts.append("ETA \(eta)")
		}
		if let distance = meetup.distanceText {
			parts.append(distance.replacingOccurrences(of: " away", with: ""))
		}
		let subtitle: String = {
			if let when = meetup.whenText, titleOverride != nil {
				return when
			}
			if !parts.isEmpty { return parts.joined(separator: " · ") }
			return meetup.venueName ?? meetup.whenText ?? ""
		}()

		self.init(
			systemImage: meetup.systemImage,
			title: title,
			subtitle: subtitle,
			label: label
		)
	}
}
