import CoreLocation
import Foundation

/// Sealed inside MEETUP blobs — notifies the Pulse sender that a meetup was accepted
/// so both devices can start the same Live Activity.
struct MeetupPayloadDTO: Codable, Sendable, Equatable {
	var meetupId: String
	var title: String
	var venueName: String?
	/// Public MapKit venue pin only — never either person's live GPS.
	var venueLatitude: Double?
	/// Public MapKit venue pin only — never either person's live GPS.
	var venueLongitude: Double?
	var meetAt: Date?
	var peerDisplayName: String
	var systemImage: String
	var createdAt: Date

	/// Venue coordinate from sealed MapKit place fields (not live location).
	var venueCoordinate: CLLocationCoordinate2D? {
		guard let venueLatitude, let venueLongitude else { return nil }
		return CLLocationCoordinate2D(latitude: venueLatitude, longitude: venueLongitude)
	}

	/// Copies venue pin from an accepted Pulse (already MapKit-sourced on send).
	static func venuePin(from pulse: PulsePayloadDTO) -> (name: String?, latitude: Double?, longitude: Double?) {
		(pulse.venueName, pulse.venueLatitude, pulse.venueLongitude)
	}
}
