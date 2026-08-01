import CoreLocation
import Foundation

struct SuggestionCard: Identifiable, Sendable {
	var id: String
	var friendID: String
	var displayName: String
	var coordinate: CLLocationCoordinate2D
	var availability: MapAvailability
	var presence: PresenceState
	var distanceMeters: CLLocationDistance
	var reason: String
	var reasonCodes: [ExplainCode]
	var factChips: [String]
	var ctaTitle: String
	var ctaSystemImage: String
	var venueName: String?
	var venueETAMinutes: Int?
	var confidence: Double
	var urgency: SuggestionUrgency
	var isModelGenerated: Bool

	var formattedDistance: String {
		if !presence.showsPreciseLocation { return "Nearby" }
		if distanceMeters < 1000 {
			return "\(Int(distanceMeters.rounded()))m away"
		}
		return String(format: "%.1fkm away", distanceMeters / 1000)
	}
}

enum SuggestionUrgency: String, Sendable, Hashable {
	case now
	case soon
	case later
}
