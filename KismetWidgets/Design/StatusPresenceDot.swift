import SwiftUI
import WidgetKit

/// Small colored presence indicator (row-trailing or inline).
struct StatusPresenceDot: View {
	let status: WidgetAppGroup.WidgetStatus
	var size: CGFloat = 8

	var body: some View {
		Circle()
			.fill(PresenceStatusColor.status(status))
			.frame(width: size, height: size)
			.widgetAccentable()
	}
}
