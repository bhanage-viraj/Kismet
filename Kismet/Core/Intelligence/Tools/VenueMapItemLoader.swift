import CoreLocation
import Foundation
import MapKit

enum VenueMapItemLoader {
	/// Rebuild an `MKMapItem` for Place Card / hours UI from a grounded venue.
	static func mapItem(for venue: GroundedVenue) async -> MKMapItem {
		if let raw = venue.mapItemIdentifier,
		   let identifier = MKMapItem.Identifier(rawValue: raw) {
			do {
				let request = MKMapItemRequest(mapItemIdentifier: identifier)
				return try await request.mapItem
			} catch {
				// Fall through to coordinate-based item.
			}
		}

		let item = MKMapItem(
			location: CLLocation(latitude: venue.latitude, longitude: venue.longitude),
			address: nil
		)
		item.name = venue.name
		return item
	}
}
