import CoreLocation
import Foundation
import FoundationModels
import MapKit

struct FindNearbyVenueTool: Tool {
	let name = "findNearbyVenue"
	let description = "Finds a real nearby cafe or food spot using MapKit near the user's location."

	private let coordinate: CLLocationCoordinate2D

	init(coordinate: CLLocationCoordinate2D) {
		self.coordinate = coordinate
	}

	@Generable
	struct Arguments {
		@Guide(description: "Search query such as coffee or lunch")
		var query: String
	}

	func call(arguments: Arguments) async throws -> String {
		let request = MKLocalSearch.Request()
		request.naturalLanguageQuery = arguments.query
		request.resultTypes = .pointOfInterest
		request.region = MKCoordinateRegion(
			center: coordinate,
			latitudinalMeters: 1_500,
			longitudinalMeters: 1_500
		)

		let response = try await MKLocalSearch(request: request).start()
		let items = response.mapItems.prefix(3)
		guard !items.isEmpty else {
			return "No venues found for \(arguments.query)."
		}

		let lines = items.map { item -> String in
			let name = item.name ?? "Place"
			let meters = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
				.distance(from: CLLocation(
					latitude: item.location.coordinate.latitude,
					longitude: item.location.coordinate.longitude
				))
			let minutes = max(1, Int((meters / 80).rounded()))
			return "\(name) (~\(minutes) min walk)"
		}
		return lines.joined(separator: "; ")
	}
}
