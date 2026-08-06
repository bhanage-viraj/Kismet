import CoreLocation
import Foundation

struct PulsePayloadDTO: Codable, Sendable, Equatable {
	var pulseId: String
	var emoji: String
	var label: String
	var expiresAt: Date
	var venueName: String?
	/// Public MapKit venue pin only — never the sender's live GPS.
	var venueLatitude: Double?
	/// Public MapKit venue pin only — never the sender's live GPS.
	var venueLongitude: Double?
	/// Intelligence / Siri draft body (includes selected venue name when available).
	var message: String?
	var createdAt: Date

	/// Venue coordinate from sealed MapKit place fields (not live location).
	var venueCoordinate: CLLocationCoordinate2D? {
		guard let venueLatitude, let venueLongitude else { return nil }
		return CLLocationCoordinate2D(latitude: venueLatitude, longitude: venueLongitude)
	}
}

struct OutgoingPulse: Identifiable, Sendable {
	var id: String
	var recipientUserIds: [String]
	var payload: PulsePayloadDTO
}

struct IncomingPulse: Identifiable, Sendable, Equatable {
	var id: String { blobId }
	var blobId: String
	var senderUserId: String
	var senderDisplayName: String
	var payload: PulsePayloadDTO
	var receivedAt: Date

	var isExpired: Bool {
		payload.expiresAt <= Date()
	}
}

enum PulseVenueFields {
	/// Extracts venue identity from a suggestion's **selected MapKit venue**.
	/// Coordinates are the place pin only — never `CLLocationManager` / proximity GPS.
	static func fromSuggestion(_ suggestion: SuggestionCard) -> (
		name: String?,
		latitude: Double?,
		longitude: Double?
	) {
		if let selected = suggestion.selectedVenue {
			// selectedVenue is always produced by VenueResolver / MapKit — never CLLocationManager.
			return (selected.name, selected.latitude, selected.longitude)
		}
		if let coordinate = suggestion.venueCoordinate, let name = suggestion.venueName {
			return (name, coordinate.latitude, coordinate.longitude)
		}
		return (suggestion.venueName, nil, nil)
	}
}
