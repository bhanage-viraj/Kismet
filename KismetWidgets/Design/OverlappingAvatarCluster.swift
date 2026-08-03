import SwiftUI
import WidgetKit

/// Stacked circular avatars — compact banner and expanded Lock Screen.
struct OverlappingAvatarCluster: View {
	let participants: [MeetupActivityAttributes.Participant]
	var size: CGFloat = 28
	var overlap: CGFloat = 10
	var maxCount: Int = 2
	/// When true, includes “You” (green ring) instead of friends-only + status dot.
	var includeYou: Bool = false
	var showsTrailingDot: Bool = true

	private var visible: [MeetupActivityAttributes.Participant] {
		if includeYou {
			return Array(participants.prefix(maxCount))
		}
		return Array(participants.filter { !$0.isYou }.prefix(maxCount))
	}

	var body: some View {
		HStack(spacing: 6) {
			HStack(spacing: -overlap) {
				ForEach(Array(visible.enumerated()), id: \.element.id) { index, person in
					PresenceAvatar(
						initials: person.initials,
						name: person.displayName,
						status: person.widgetStatus,
						size: size,
						ringWidth: person.isYou ? 2.25 : 1.5,
						ringGap: 1.25,
						ringTrackColor: Color(.systemBackground),
						photo: WidgetAppGroup.loadAvatarImage(fileName: person.avatarFileName),
						showsStatusDot: false,
						ringColor: person.isYou
							? PresenceStatusColor.free
							: PresenceStatusColor.status(person.widgetStatus)
					)
					.overlay {
						Circle()
							.strokeBorder(Color(.systemBackground), lineWidth: 1.5)
					}
					.zIndex(Double(index))
				}
			}

			if showsTrailingDot, !includeYou {
				StatusPresenceDot(status: .free, size: 8)
			}
		}
	}
}
