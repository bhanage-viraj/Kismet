import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen Live Activity banner (~338×88):
/// activity chip + venue headline + ETA + avatar cluster.
struct MeetupActivityCompactView: View {
	let attributes: MeetupActivityAttributes
	let state: MeetupActivityAttributes.ContentState

	var body: some View {
		Group {
			if state.isEnded {
				ended
			} else {
				active
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.activityBackgroundTint(PresenceStatusColor.elevatedCard.opacity(0.92))
		.activitySystemActionForegroundColor(.primary)
	}

	private var active: some View {
		HStack(spacing: 12) {
			MeetupIconChip(
				systemImage: attributes.systemImage,
				size: 40,
				cornerRadius: 11,
				symbolFont: .body.weight(.semibold),
				style: .solid
			)

			VStack(alignment: .leading, spacing: 2) {
				Text(attributes.headline)
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)

				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
			}

			Spacer(minLength: 4)

			OverlappingAvatarCluster(
				participants: attributes.participants,
				size: 28,
				overlap: 10,
				maxCount: 2,
				showsTrailingDot: true
			)

			Image(systemName: "chevron.up")
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.tertiary)
		}
	}

	private var ended: some View {
		HStack(spacing: 12) {
			MeetupIconChip(
				systemImage: attributes.systemImage,
				size: 40,
				cornerRadius: 11,
				style: .solid
			)

			VStack(alignment: .leading, spacing: 2) {
				Text(attributes.headline)
					.font(.subheadline.weight(.bold))
					.foregroundStyle(.primary)
					.lineLimit(1)
				Text("Meetup happened")
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer(minLength: 0)

			Button(intent: EndMeetupLiveActivityIntent()) {
				Image(systemName: "xmark")
					.font(.system(size: 11, weight: .bold))
					.foregroundStyle(.secondary)
					.frame(width: 28, height: 28)
					.background(Circle().fill(Color.primary.opacity(0.08)))
					.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Dismiss")
		}
	}

	private var subtitle: String {
		var parts: [String] = []
		if !state.etaText.isEmpty, state.etaText != "—" {
			parts.append("ETA \(state.etaText)")
		}
		if !state.distanceText.isEmpty, state.distanceText != "—" {
			parts.append(state.distanceText)
		}
		return parts.joined(separator: " · ")
	}
}
