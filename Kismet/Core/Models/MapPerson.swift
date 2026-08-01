import CoreLocation
import Foundation
import SwiftUI

enum MapAvailability: String, Codable, Hashable, Sendable {
	case free
	case busy
	case unknown

	var statusColor: Color {
		switch self {
		case .free: KismetTheme.Status.free
		case .busy: KismetTheme.Status.busy
		case .unknown: KismetTheme.Status.unknown
		}
	}
}

struct MapPerson: Identifiable, Hashable, Sendable {
	let id: String
	let displayName: String
	var coordinate: CLLocationCoordinate2D
	var availability: MapAvailability
	var distanceMeters: CLLocationDistance
	var insightSummary: String
	var intentLabel: String
	var neighborhoodLabel: String
	var mutualFriendCount: Int
	var accentSystemImage: String
	var ctaTitle: String
	var ctaSystemImage: String

	var formattedDistance: String {
		if distanceMeters < 1000 {
			return "\(Int(distanceMeters.rounded()))m away"
		}
		let km = distanceMeters / 1000
		return String(format: "%.1fkm away", km)
	}

	var formattedWalkingMinutes: String {
		let minutes = max(1, Int((distanceMeters / 80).rounded()))
		return "\(minutes) mins away"
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: MapPerson, rhs: MapPerson) -> Bool {
		lhs.id == rhs.id
	}
}
