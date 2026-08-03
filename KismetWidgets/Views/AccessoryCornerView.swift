import SwiftUI
import WidgetKit

/// `.accessoryCorner` — watchOS complication: people glyph + numeric badge.
/// Not registered in the iOS widget’s `supportedFamilies`; kept ready for a watch target.
struct FriendsBadgeCornerView: View {
	let freeCount: Int

	var body: some View {
		ZStack {
			AccessoryWidgetBackground()
			Image(systemName: "person.2.fill")
				.font(.title3.weight(.semibold))
				.foregroundStyle(PresenceStatusColor.free)
		}
		.widgetAccentable()
		.widgetLabel {
			Text("\(freeCount)")
		}
	}
}

typealias AccessoryCornerView = FriendsBadgeCornerView

#if os(watchOS)
#Preview("Corner", as: .accessoryCorner) {
	FriendsBadgeCornerView(freeCount: 2)
}
#else
#Preview("Corner") {
	FriendsBadgeCornerView(freeCount: 2)
		.padding()
}
#endif
