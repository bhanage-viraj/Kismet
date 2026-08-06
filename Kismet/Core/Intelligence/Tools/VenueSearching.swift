import CoreLocation
import Foundation
import MapKit

protocol VenueSearching: Sendable {
	func search(query: VenueQuery) async throws -> [MKMapItem]
}

/// Live MapKit `MKLocalSearch` around the query origin.
struct NearbyVenueSearch: VenueSearching {
	var searchRadiusMeters: CLLocationDistance = 3_000
	var maxRawResults: Int = 15

	func search(query: VenueQuery) async throws -> [MKMapItem] {
		let request = MKLocalSearch.Request()
		request.naturalLanguageQuery = query.type.naturalLanguageQuery
		request.resultTypes = .pointOfInterest
		request.region = MKCoordinateRegion(
			center: query.origin,
			latitudinalMeters: searchRadiusMeters,
			longitudinalMeters: searchRadiusMeters
		)

		let response = try await MKLocalSearch(request: request).start()
		return Array(response.mapItems.prefix(maxRawResults))
	}
}

/// Fixture-based search for unit tests (no live MapKit network).
struct MockVenueSearch: VenueSearching {
	var items: [MKMapItem]
	var error: Error?

	init(items: [MKMapItem] = [], error: Error? = nil) {
		self.items = items
		self.error = error
	}

	func search(query: VenueQuery) async throws -> [MKMapItem] {
		if let error { throw error }
		_ = query
		return items
	}
}
