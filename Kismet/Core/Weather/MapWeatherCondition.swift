import Foundation

/// Visual weather states for the map atmosphere overlay.
enum MapWeatherCondition: String, CaseIterable, Identifiable, Sendable {
	case clear
	case cloudy
	case drizzle
	case rain
	case heavyRain
	case thunderstorm
	case snow
	case fog

	var id: String { rawValue }

	var title: String {
		switch self {
		case .clear: "Clear"
		case .cloudy: "Cloudy"
		case .drizzle: "Drizzle"
		case .rain: "Rain"
		case .heavyRain: "Heavy Rain"
		case .thunderstorm: "Thunderstorm"
		case .snow: "Snow"
		case .fog: "Fog"
		}
	}

	var symbolName: String {
		switch self {
		case .clear: "sun.max.fill"
		case .cloudy: "cloud.fill"
		case .drizzle: "cloud.drizzle.fill"
		case .rain: "cloud.rain.fill"
		case .heavyRain: "cloud.heavyrain.fill"
		case .thunderstorm: "cloud.bolt.rain.fill"
		case .snow: "cloud.snow.fill"
		case .fog: "cloud.fog.fill"
		}
	}

	/// Baseline particle density / opacity scale used when intensity is 1.
	var baseIntensity: Double {
		switch self {
		case .clear: 0
		case .cloudy: 0.25
		case .drizzle: 0.35
		case .rain: 0.65
		case .heavyRain: 0.95
		case .thunderstorm: 0.9
		case .snow: 0.7
		case .fog: 0.8
		}
	}

	var showsParticles: Bool {
		switch self {
		case .clear, .cloudy: false
		default: true
		}
	}
}
