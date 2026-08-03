import SwiftUI
import WidgetKit

/// figure.walk → dashed green progress → pin.
struct JourneyProgressTrack: View {
	var progress: Double

	private var clamped: CGFloat {
		CGFloat(min(max(progress, 0), 1))
	}

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: "figure.walk")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(PresenceStatusColor.free)
				.widgetAccentable()

			GeometryReader { geo in
				let width = max(geo.size.width, 1)
				let midY = geo.size.height / 2
				let x = max(4, min(width - 4, width * clamped))

				ZStack(alignment: .leading) {
					Capsule()
						.fill(Color.primary.opacity(0.14))
						.frame(height: 2)
						.position(x: width / 2, y: midY)

					Path { path in
						path.move(to: CGPoint(x: 0, y: midY))
						path.addLine(to: CGPoint(x: x, y: midY))
					}
					.stroke(
						PresenceStatusColor.free,
						style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4])
					)
					.widgetAccentable()

					Circle()
						.fill(PresenceStatusColor.free)
						.frame(width: 8, height: 8)
						.position(x: x, y: midY)
						.widgetAccentable()
				}
			}
			.frame(height: 16)

			Image(systemName: "mappin")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(.secondary)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Journey progress")
		.accessibilityValue("\(Int(clamped * 100)) percent")
	}
}
