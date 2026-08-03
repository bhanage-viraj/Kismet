import SwiftUI
import WidgetKit

/// `.accessoryCircular` — free-friend count inside a capacity gauge.
struct FriendsFreeCircularView: View {
	let freeCount: Int
	/// Nearby friends used as the gauge capacity (falls back to `freeCount`).
	var nearbyCount: Int = 0

	private var progress: Double {
		guard freeCount > 0 else { return 0 }
		let capacity = max(nearbyCount, freeCount, 1)
		return min(1, Double(freeCount) / Double(capacity))
	}

	var body: some View {
		Gauge(value: progress) {
			Text("Friends free")
		} currentValueLabel: {
			VStack(spacing: 0) {
				Text("\(freeCount)")
					.font(.system(size: 26, weight: .bold, design: .rounded))
					.minimumScaleFactor(0.7)
					.lineLimit(1)
				Text("friends")
					.font(.system(size: 9, weight: .semibold))
					.lineLimit(1)
				Text("free")
					.font(.system(size: 9, weight: .semibold))
					.lineLimit(1)
			}
			.multilineTextAlignment(.center)
		}
		.gaugeStyle(.accessoryCircularCapacity)
		.tint(PresenceStatusColor.free)
		.widgetAccentable()
	}
}

typealias AccessoryCircularView = FriendsFreeCircularView

#Preview(as: .accessoryCircular) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
