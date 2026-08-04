import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct MeetupLiveActivity: Widget {
	var body: some WidgetConfiguration {
		ActivityConfiguration(for: MeetupActivityAttributes.self) { context in
			lockScreen(context: context)
		} dynamicIsland: { context in
			DynamicIsland {
				// Icon left / meet place right — inset so the Island’s rounded ends don’t clip.
				DynamicIslandExpandedRegion(.leading) {
					MeetupIconChip(
						systemImage: context.attributes.systemImage,
						size: 24,
						cornerRadius: 7,
						symbolFont: .system(size: 11, weight: .semibold),
						style: .solid
					)
					.padding(.leading, 12)
				}

				DynamicIslandExpandedRegion(.trailing) {
					Text(context.attributes.headline)
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(.primary)
						.lineLimit(1)
						.minimumScaleFactor(0.65)
						.multilineTextAlignment(.trailing)
						.padding(.trailing, 12)
				}

				DynamicIslandExpandedRegion(.center) {
					EmptyView()
				}

				DynamicIslandExpandedRegion(.bottom) {
					MeetupActivityExpandedContent(
						attributes: context.attributes,
						state: context.state,
						showsHeader: false,
						showsCollapseControl: false,
						showsEndControl: !context.state.isEnded,
						compact: true
					)
					.padding(.horizontal, 4)
					.padding(.top, 2)
				}
			} compactLeading: {
				MeetupIslandIcon(systemImage: context.attributes.systemImage)
			} compactTrailing: {
				if context.state.isEnded {
					Image(systemName: "checkmark")
						.font(.caption.weight(.bold))
						.foregroundStyle(PresenceStatusColor.free)
						.widgetAccentable()
				} else {
					Text(context.state.etaText)
						.font(.caption.weight(.semibold))
						.foregroundStyle(PresenceStatusColor.free)
						.widgetAccentable()
						.minimumScaleFactor(0.7)
				}
			} minimal: {
				if context.state.isEnded {
					Image(systemName: "checkmark")
						.font(.body.weight(.bold))
						.foregroundStyle(PresenceStatusColor.free)
						.widgetAccentable()
				} else {
					MeetupIslandIcon(systemImage: context.attributes.systemImage)
				}
			}
			.keylineTint(PresenceStatusColor.free)
			.widgetURL(WidgetDeepLink.meetup)
		}
	}

	@ViewBuilder
	private func lockScreen(context: ActivityViewContext<MeetupActivityAttributes>) -> some View {
		if context.state.isEnded {
			MeetupActivityCompactView(attributes: context.attributes, state: context.state)
				.widgetURL(WidgetDeepLink.meetup)
		} else if context.state.isExpanded {
			MeetupActivityExpandedView(attributes: context.attributes, state: context.state)
				.widgetURL(WidgetDeepLink.meetup)
		} else {
			Button(intent: ExpandMeetupLiveActivityIntent()) {
				MeetupActivityCompactView(attributes: context.attributes, state: context.state)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
		}
	}
}

// MARK: - Previews

#Preview("1 · Lock Screen Compact", as: .content, using: MeetupActivityAttributes.preview) {
	MeetupLiveActivity()
} contentStates: {
	MeetupActivityAttributes.ContentState.preview
	MeetupActivityAttributes.ContentState.ended
}

#Preview("2 · Lock Screen Expanded", as: .content, using: MeetupActivityAttributes.preview) {
	MeetupLiveActivity()
} contentStates: {
	MeetupActivityAttributes.ContentState.previewExpanded
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: MeetupActivityAttributes.preview) {
	MeetupLiveActivity()
} contentStates: {
	MeetupActivityAttributes.ContentState.preview
}

#Preview("Island Minimal", as: .dynamicIsland(.minimal), using: MeetupActivityAttributes.preview) {
	MeetupLiveActivity()
} contentStates: {
	MeetupActivityAttributes.ContentState.preview
	MeetupActivityAttributes.ContentState.ended
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: MeetupActivityAttributes.preview) {
	MeetupLiveActivity()
} contentStates: {
	MeetupActivityAttributes.ContentState.preview
}
