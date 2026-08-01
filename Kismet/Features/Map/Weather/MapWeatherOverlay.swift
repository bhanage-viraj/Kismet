import SwiftUI

/// Full-screen weather atmosphere layered above map + chrome (Weather-app style particles).
struct MapWeatherOverlay: View {
	let condition: MapWeatherCondition
	let intensity: Double
	let obstacles: [WeatherObstacle]

	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var engine = WeatherParticleEngine()

	var body: some View {
		GeometryReader { proxy in
			let overlayGlobal = proxy.frame(in: .global)
			let localObstacles = obstacles.map {
				$0.convertedToOverlayLocal(overlayFrameInGlobal: overlayGlobal)
			}

			SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !shouldAnimate)) { timeline in
				Canvas { context, size in
					if shouldAnimate {
						engine.tick(
							date: timeline.date,
							size: size,
							condition: condition,
							intensity: intensity,
							obstacles: localObstacles
						)
					}
					engine.draw(
						context: context,
						size: size,
						condition: condition,
						intensity: intensity
					)
				}
			}
		}
		.allowsHitTesting(false)
		.id(condition.rawValue)
		.opacity(condition == .clear ? 0 : 1)
		.animation(.easeInOut(duration: 0.45), value: condition)
	}

	private var shouldAnimate: Bool {
		guard !reduceMotion else { return false }
		switch condition {
		case .drizzle, .rain, .heavyRain, .thunderstorm, .snow:
			return intensity > 0.02
		case .clear, .cloudy, .fog:
			return false
		}
	}
}
