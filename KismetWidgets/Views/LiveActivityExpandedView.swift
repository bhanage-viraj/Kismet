import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Expanded Lock Screen Live Activity — compact height, no overflow:
/// header → stats → journey → avatars + names (same row).
struct MeetupActivityExpandedView: View {
	let attributes: MeetupActivityAttributes
	let state: MeetupActivityAttributes.ContentState
	var showsCollapseControl: Bool = true

	var body: some View {
		Group {
			if state.isEnded {
				MeetupActivityExpandedEnded(attributes: attributes)
			} else {
				MeetupActivityExpandedContent(
					attributes: attributes,
					state: state,
					showsHeader: true,
					showsCollapseControl: showsCollapseControl
				)
			}
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 12)
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.activityBackgroundTint(Color.black.opacity(0.82))
		.activitySystemActionForegroundColor(.white)
	}
}

/// Shared expanded body used by Lock Screen + Dynamic Island.
struct MeetupActivityExpandedContent: View {
	let attributes: MeetupActivityAttributes
	let state: MeetupActivityAttributes.ContentState
	var showsHeader: Bool = true
	var showsCollapseControl: Bool = false
	var showsEndControl: Bool = false
	var compact: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: compact ? 8 : 10) {
			if showsHeader {
				MeetupActivityExpandedHeader(
					attributes: attributes,
					showsCollapseControl: showsCollapseControl,
					showsEndControl: showsEndControl || showsCollapseControl,
					compact: compact
				)
			} else if showsEndControl {
				HStack {
					Spacer(minLength: 0)
					Button(intent: EndMeetupLiveActivityIntent()) {
						Text("End")
							.font(.system(size: 12, weight: .semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 10)
							.padding(.vertical, 5)
							.background(Capsule().fill(Color.red.opacity(0.85)))
							.contentShape(Capsule())
					}
					.buttonStyle(.plain)
					.accessibilityLabel("End meetup")
				}
			}
			MeetupActivityExpandedStats(state: state, compact: compact)
			JourneyProgressTrack(progress: state.progress)
			MeetupActivityExpandedPeople(attributes: attributes, compact: compact)
		}
	}
}

struct MeetupActivityExpandedHeader: View {
	let attributes: MeetupActivityAttributes
	var showsCollapseControl: Bool = false
	var showsEndControl: Bool = false
	var compact: Bool = false

	private var chipSize: CGFloat { compact ? 24 : 28 }
	private var titleSize: CGFloat { compact ? 14 : 15 }

	var body: some View {
		HStack(alignment: .center, spacing: 8) {
			MeetupIconChip(
				systemImage: attributes.systemImage,
				size: chipSize,
				cornerRadius: compact ? 7 : 8,
				symbolFont: .system(size: compact ? 11 : 12, weight: .semibold),
				style: .solid
			)

			Text(attributes.headline)
				.font(.system(size: titleSize, weight: .semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)

			Spacer(minLength: 4)

			if showsEndControl {
				Button(intent: EndMeetupLiveActivityIntent()) {
					Text("End")
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 10)
						.padding(.vertical, 6)
						.background(Capsule().fill(Color.red.opacity(0.85)))
						.contentShape(Capsule())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("End meetup")
			}

			if showsCollapseControl {
				Button(intent: CollapseMeetupLiveActivityIntent()) {
					Image(systemName: "chevron.down")
						.font(.system(size: 10, weight: .bold))
						.foregroundStyle(.secondary)
						.frame(width: 26, height: 26)
						.background(Circle().fill(Color.primary.opacity(0.08)))
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Collapse")
			}
		}
	}
}

struct MeetupActivityExpandedStats: View {
	let state: MeetupActivityAttributes.ContentState
	var compact: Bool = false

	var body: some View {
		HStack(alignment: .top, spacing: compact ? 16 : 20) {
			statColumn(label: "Arriving in", value: state.etaText)
			statColumn(label: "Distance", value: state.distanceText)
			Spacer(minLength: 0)
		}
	}

	private func statColumn(label: String, value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(label)
				.font(.system(size: compact ? 10 : 11, weight: .medium))
				.foregroundStyle(.secondary)
			Text(value)
				.font(.system(size: compact ? 17 : 20, weight: .bold, design: .rounded))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)
		}
	}
}

struct MeetupActivityExpandedPeople: View {
	let attributes: MeetupActivityAttributes
	var compact: Bool = false

	private var people: [MeetupActivityAttributes.Participant] {
		Array(attributes.participants.prefix(3))
	}

	var body: some View {
		HStack(spacing: 10) {
			OverlappingAvatarCluster(
				participants: people,
				size: compact ? 24 : 28,
				overlap: compact ? 8 : 10,
				maxCount: 3,
				includeYou: true,
				showsTrailingDot: false
			)

			Text(people.map(\.displayName).joined(separator: " · "))
				.font(.system(size: compact ? 12 : 13, weight: .semibold))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.minimumScaleFactor(0.75)

			Spacer(minLength: 0)
		}
	}
}

struct MeetupActivityExpandedEnded: View {
	let attributes: MeetupActivityAttributes

	var body: some View {
		HStack(spacing: 8) {
			MeetupIconChip(
				systemImage: attributes.systemImage,
				size: 28,
				cornerRadius: 8,
				symbolFont: .system(size: 12, weight: .semibold),
				style: .solid
			)
			VStack(alignment: .leading, spacing: 2) {
				Text(attributes.headline)
					.font(.system(size: 15, weight: .semibold))
					.lineLimit(1)
				Text("Meetup happened")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)

			Button(intent: EndMeetupLiveActivityIntent()) {
				Image(systemName: "xmark")
					.font(.system(size: 11, weight: .bold))
					.foregroundStyle(.secondary)
					.frame(width: 26, height: 26)
					.background(Circle().fill(Color.primary.opacity(0.08)))
					.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Dismiss")
		}
	}
}

// MARK: - Dynamic Island shared pieces

struct MeetupIslandIcon: View {
	var systemImage: String

	var body: some View {
		Image(systemName: systemImage)
			.font(.body.weight(.semibold))
			.foregroundStyle(PresenceStatusColor.free)
			.widgetAccentable()
	}
}
