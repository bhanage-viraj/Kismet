import CoreLocation
import Foundation
import WeatherKit

enum WeatherConditionKind: String, Sendable, Hashable {
	case clear
	case cloudy
	case rain
	case snow
	case hot
	case cold
	case unknown
}

struct WeatherSlice: Sendable, Hashable {
	var condition: WeatherConditionKind
	var summary: String?

	static let unknown = WeatherSlice(condition: .unknown, summary: nil)

	var favorsIndoor: Bool {
		switch condition {
		case .rain, .snow, .cold: true
		default: false
		}
	}

	var favorsOutdoor: Bool {
		switch condition {
		case .clear, .hot: true
		default: false
		}
	}
}

struct WeatherContextProvider: ContextProviding {
	var coordinate: CLLocationCoordinate2D

	func current() async -> WeatherSlice {
		let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
		do {
			let weather = try await WeatherService.shared.weather(for: location)
			let current = weather.currentWeather
			let kind = Self.mapCondition(current.condition, temperature: current.temperature)
			return WeatherSlice(
				condition: kind,
				summary: current.condition.description
			)
		} catch {
			return .unknown
		}
	}

	private static func mapCondition(
		_ condition: WeatherCondition,
		temperature: Measurement<UnitTemperature>
	) -> WeatherConditionKind {
		let celsius = temperature.converted(to: .celsius).value
		if celsius >= 33 { return .hot }
		if celsius <= 12 { return .cold }

		switch condition {
		case .rain, .heavyRain, .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms,
			 .strongStorms, .thunderstorms, .tropicalStorm, .hurricane, .hail, .sleet,
			 .freezingRain, .freezingDrizzle, .drizzle:
			return .rain
		case .snow, .heavySnow, .flurries, .sunFlurries, .blowingSnow, .blizzard, .wintryMix:
			return .snow
		case .clear, .mostlyClear, .hot:
			return .clear
		case .cloudy, .mostlyCloudy, .partlyCloudy, .foggy, .haze, .smoky, .breezy, .windy:
			return .cloudy
		default:
			return .unknown
		}
	}
}
