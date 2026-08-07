import CoreLocation
import Foundation
import FoundationModels
import MapKit

struct FindNearbyVenueTool: Tool {
	let name = "findNearbyVenue"
	let description = "Finds a real nearby cafe or food spot using MapKit near the user's location."

	private let coordinate: CLLocationCoordinate2D
	private let searcher: any VenueSearching

	init(coordinate: CLLocationCoordinate2D, searcher: any VenueSearching = NearbyVenueSearch()) {
		self.coordinate = coordinate
		self.searcher = searcher
	}

	@Generable
	struct Arguments {
		@Guide(description: "Search query such as coffee or lunch")
		var query: String
	}

	func call(arguments: Arguments) async throws -> String {
		let queryType = VenueQueryType.infer(fromPlaceTypeSignal: arguments.query) ?? .coffee
		let venueQuery = VenueQuery(type: queryType, origin: coordinate, transportPreference: .walking)
		let items = try await searcher.search(query: venueQuery)
		guard let candidates = VenueResolver.resolve(candidates: items, query: venueQuery) else {
			return "No venues found for \(arguments.query)."
		}

		// Tool output for the model: suggested + up to 2 alternatives (display ETA only).
		let lines = candidates.all.prefix(3).map { venue -> String in
			let eta = venue.displayETALabel ?? "\(Int(venue.distanceMeters.rounded())) m"
			return "\(venue.name) (~\(eta))"
		}
		return lines.joined(separator: "; ")
	}
}
