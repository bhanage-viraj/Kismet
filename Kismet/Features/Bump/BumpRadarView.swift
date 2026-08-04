import SwiftUI

/// Concentric-ring radar. Direction wedge when UWB provides azimuth; distance-only otherwise.
struct BumpRadarView: View {
	var sample: NearbyRangeSample?
	var peerLabel: String
	var showsDirectionHint: Bool

	/// Demo / preview: meters mapped onto the outer ring.
	private let maxRangeMeters: CGFloat = 4.0

	var body: some View {
		GeometryReader { geo in
			let side = min(geo.size.width, geo.size.height)
			let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
			let radius = side * 0.42

			ZStack {
				ForEach([0.33, 0.66, 1.0], id: \.self) { fraction in
					Circle()
						.stroke(KismetTheme.Map.ringStroke, lineWidth: 1)
						.frame(width: radius * 2 * fraction, height: radius * 2 * fraction)
						.position(center)
				}

				Circle()
					.fill(KismetTheme.Map.userPulse)
					.frame(width: 14, height: 14)
					.overlay {
						Circle()
							.stroke(Color.white.opacity(0.9), lineWidth: 2)
					}
					.position(center)
					.accessibilityLabel("You")

				if let sample, let distance = sample.distance {
					peerBlip(
						distance: CGFloat(distance),
						direction: sample.direction,
						center: center,
						radius: radius
					)
				} else {
					Text("Searching…")
						.font(.caption.weight(.medium))
						.foregroundStyle(.secondary)
						.position(x: center.x, y: center.y + radius + 20)
				}
			}
			.frame(width: geo.size.width, height: geo.size.height)
		}
		.aspectRatio(1, contentMode: .fit)
		.overlay(alignment: .bottom) {
			VStack(spacing: 4) {
				if let distance = sample?.distance {
					Text(distanceLabel(distance))
						.font(.title3.weight(.semibold).monospacedDigit())
					Text(peerLabel)
						.font(.subheadline.weight(.medium))
					if sample?.direction == nil, showsDirectionHint {
						Text("Move phones for direction")
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			.padding(.bottom, 4)
		}
	}

	@ViewBuilder
	private func peerBlip(
		distance: CGFloat,
		direction: SIMD3<Float>?,
		center: CGPoint,
		radius: CGFloat
	) -> some View {
		let angle = PolarPosition.azimuth(from: direction) ?? PolarPosition.defaultAngle
		let ring = PolarPosition.ringRadius(
			distance: distance,
			maxRange: maxRangeMeters,
			outerRadius: radius
		)
		let point = PolarPosition.point(
			distance: distance,
			maxRange: maxRangeMeters,
			center: center,
			outerRadius: radius,
			angle: angle
		)

		ZStack {
			if direction != nil {
				Capsule()
					.fill(KismetTheme.Status.free.opacity(0.25))
					.frame(width: 10, height: ring)
					.offset(y: -ring / 2)
					.rotationEffect(.radians(Double(PolarPosition.wedgeRotation(for: angle))))
					.position(center)
			}

			Circle()
				.fill(KismetTheme.Status.free)
				.frame(width: 18, height: 18)
				.shadow(color: KismetTheme.Status.free.opacity(0.45), radius: 6, y: 1)
				.position(point)
				.accessibilityLabel("\(peerLabel), \(distanceLabel(Float(distance)))")
		}
		.animation(.snappy(duration: 0.25), value: distance)
		.animation(.snappy(duration: 0.25), value: direction.map { "\($0.x),\($0.y),\($0.z)" })
	}

	private func distanceLabel(_ meters: Float) -> String {
		if meters < 1 {
			return String(format: "%.0f cm", Double(meters) * 100)
		}
		return String(format: "%.1f m", meters)
	}
}

#Preview("With direction") {
	BumpRadarView(
		sample: NearbyRangeSample(
			distance: 1.4,
			direction: SIMD3<Float>(0.3, 0, -0.9),
			timestamp: .now
		),
		peerLabel: "Ada",
		showsDirectionHint: true
	)
	.padding()
}

#Preview("Distance only") {
	BumpRadarView(
		sample: NearbyRangeSample(distance: 2.1, direction: nil, timestamp: .now),
		peerLabel: "Grace",
		showsDirectionHint: true
	)
	.padding()
}
