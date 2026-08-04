import CoreLocation
import Foundation

/// How the selected Presence State shapes what we seal into LOCATION blobs.
enum PresenceLocationPolicy {
	/// Neighborhood-scale grid for Approximate / Eclipse publishes (~500 m).
	static let approximateGridMeters: CLLocationDistance = 500

	/// Builds the sealed plaintext for a friend LOCATION blob.
	static func payload(
		from location: CLLocation,
		presence: PresenceState,
		at date: Date = Date()
	) -> LocationPayloadDTO {
		let share = shareCoordinate(from: location, presence: presence)
		return LocationPayloadDTO(
			lat: share.latitude,
			lon: share.longitude,
			accuracy: share.accuracy,
			at: date,
			mode: presence.rawValue
		)
	}

	/// Precise for Available / Friends Only; quantized for Approximate / Eclipse.
	static func shareCoordinate(
		from location: CLLocation,
		presence: PresenceState
	) -> (latitude: Double, longitude: Double, accuracy: Double?) {
		switch presence {
		case .available, .friendsOnly:
			let accuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
			return (
				location.coordinate.latitude,
				location.coordinate.longitude,
				accuracy
			)
		case .approximate, .eclipse:
			let fuzzed = quantize(location.coordinate, gridMeters: approximateGridMeters)
			return (fuzzed.latitude, fuzzed.longitude, approximateGridMeters)
		}
	}

	/// Snaps a coordinate to a meter grid so Approximate never leaks a precise pin.
	static func quantize(
		_ coordinate: CLLocationCoordinate2D,
		gridMeters: CLLocationDistance
	) -> CLLocationCoordinate2D {
		let latMetersPerDegree = 111_320.0
		let lonMetersPerDegree = max(
			1.0,
			111_320.0 * cos(coordinate.latitude * .pi / 180)
		)
		let latStep = gridMeters / latMetersPerDegree
		let lonStep = gridMeters / lonMetersPerDegree
		let lat = (coordinate.latitude / latStep).rounded() * latStep
		let lon = (coordinate.longitude / lonStep).rounded() * lonStep
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}
}
