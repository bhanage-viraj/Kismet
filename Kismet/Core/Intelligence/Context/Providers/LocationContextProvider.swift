import CoreLocation
import Foundation

struct LocationSnapshot: Sendable {
	var coordinate: CLLocationCoordinate2D
	var placeName: String?
	var accuracy: Double?
}

struct LocationContextProvider: ContextProviding {
	private let coordinate: CLLocationCoordinate2D
	private let placeName: String?
	private let accuracy: Double?

	init(coordinate: CLLocationCoordinate2D, placeName: String?, accuracy: Double?) {
		self.coordinate = coordinate
		self.placeName = placeName
		self.accuracy = accuracy
	}

	func current() async -> LocationSnapshot {
		LocationSnapshot(coordinate: coordinate, placeName: placeName, accuracy: accuracy)
	}
}
