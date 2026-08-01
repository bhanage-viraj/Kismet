import CoreLocation
import Foundation
import Observation
import WeatherKit

/// Fetches live weather via WeatherKit for the map atmosphere overlay.
@MainActor
@Observable
final class MapWeatherController {
	private(set) var condition: MapWeatherCondition = .clear
	private(set) var intensity: Double = 0
	private(set) var sourceLabel: String = "Idle"
	private(set) var lastError: String?

	private let weatherService = WeatherService.shared
	private var lastFetchCoordinate: CLLocationCoordinate2D?
	private var lastFetchDate: Date?

	private let minimumRefetchInterval: TimeInterval = 10 * 60
	private let minimumCoordinateDeltaMeters: CLLocationDistance = 2_000

	func refreshIfNeeded(at coordinate: CLLocationCoordinate2D) async {
		if let lastFetchDate,
		   let lastFetchCoordinate,
		   Date().timeIntervalSince(lastFetchDate) < minimumRefetchInterval {
			let last = CLLocation(latitude: lastFetchCoordinate.latitude, longitude: lastFetchCoordinate.longitude)
			let next = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
			if next.distance(from: last) < minimumCoordinateDeltaMeters {
				return
			}
		}

		await fetchLive(at: coordinate)
	}

	func forceRefresh(at coordinate: CLLocationCoordinate2D) async {
		await fetchLive(at: coordinate)
	}

	private func fetchLive(at coordinate: CLLocationCoordinate2D) async {
		sourceLabel = "Fetching…"
		do {
			let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
			let current = try await weatherService.weather(for: location).currentWeather
			let mapped = Self.map(condition: current.condition, precip: current.precipitationIntensity)
			condition = mapped.condition
			intensity = mapped.intensity
			lastFetchCoordinate = coordinate
			lastFetchDate = Date()
			lastError = nil
			sourceLabel = "Live · WeatherKit"
		} catch {
			lastError = error.localizedDescription
			sourceLabel = "Live unavailable"
			// Keep last known values so a transient failure doesn't wipe the scene.
		}
	}

	private static func map(
		condition: WeatherCondition,
		precip: Measurement<UnitSpeed>
	) -> (condition: MapWeatherCondition, intensity: Double) {
		let mmPerHour = precip.converted(to: .metersPerSecond).value * 3_600_000
		let precipScale = min(max(mmPerHour / 12.0, 0), 1)

		switch condition {
		case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .hail:
			return (.thunderstorm, max(0.7, precipScale))

		case .heavyRain, .tropicalStorm, .hurricane:
			return (.heavyRain, max(0.8, precipScale))

		case .rain, .sunShowers, .freezingRain, .wintryMix, .freezingDrizzle:
			return (.rain, max(0.45, precipScale))

		case .drizzle:
			return (.drizzle, max(0.25, precipScale * 0.7))

		case .snow, .heavySnow, .flurries, .blowingSnow, .blizzard, .sleet, .sunFlurries:
			return (.snow, max(0.5, precipScale))

		case .foggy, .haze, .smoky, .blowingDust:
			return (.fog, 0.75)

		case .cloudy, .mostlyCloudy, .partlyCloudy:
			return (.cloudy, 0.3)

		case .clear, .mostlyClear, .hot, .frigid, .breezy, .windy:
			return (.clear, 0)

		@unknown default:
			return (.clear, 0)
		}
	}
}
