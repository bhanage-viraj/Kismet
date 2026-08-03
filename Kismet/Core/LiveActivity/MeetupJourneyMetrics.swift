import CoreLocation
import Foundation

/// Computes Live Activity ETA / distance / progress from movement + optional meet time.
enum MeetupJourneyMetrics {
	/// Fallback walking speed (~4.9 km/h) when Core Location speed is unavailable.
	static let defaultWalkingSpeedMps: CLLocationSpeed = 1.35
	/// Treat as “at venue” within this radius.
	static let arrivedRadiusMeters: CLLocationDistance = 45

	struct Snapshot: Equatable, Sendable {
		var etaText: String
		var distanceText: String
		var progress: Double
		var distanceMeters: CLLocationDistance
		var isArrived: Bool
	}

	static func snapshot(
		from location: CLLocation,
		venueLatitude: Double,
		venueLongitude: Double,
		meetAt: Date?,
		initialDistanceMeters: Double?,
		now: Date = .now
	) -> Snapshot {
		let venue = CLLocation(latitude: venueLatitude, longitude: venueLongitude)
		let distance = max(0, location.distance(from: venue))
		let arrived = distance <= arrivedRadiusMeters

		let travelMinutes = travelETAMinutes(distance: distance, location: location)
		let meetMinutes: Int? = meetAt.map { minutesUntil($0, from: now) }

		// Arriving-in: movement-based while en route; meet-time countdown once at the pin.
		let etaMinutes: Int = {
			if arrived {
				return meetMinutes ?? 0
			}
			return travelMinutes
		}()

		let baseline = max(initialDistanceMeters ?? distance, distance, 1)
		let progress: Double = {
			if arrived { return 1 }
			return min(1, max(0, 1 - (distance / baseline)))
		}()

		return Snapshot(
			etaText: formatMinutes(etaMinutes),
			distanceText: formatDistance(distance),
			progress: progress,
			distanceMeters: distance,
			isArrived: arrived
		)
	}

	/// Initial snapshot when starting an activity (no live speed yet).
	static func initialSnapshot(
		from location: CLLocation?,
		venueLatitude: Double,
		venueLongitude: Double,
		meetAt: Date?,
		now: Date = .now
	) -> (snapshot: Snapshot, initialDistance: Double) {
		guard let location else {
			let meetMin = meetAt.map { minutesUntil($0, from: now) } ?? 5
			return (
				Snapshot(
					etaText: formatMinutes(meetMin),
					distanceText: "—",
					progress: 0,
					distanceMeters: 0,
					isArrived: false
				),
				0
			)
		}
		let venue = CLLocation(latitude: venueLatitude, longitude: venueLongitude)
		let distance = max(0, location.distance(from: venue))
		let snap = snapshot(
			from: location,
			venueLatitude: venueLatitude,
			venueLongitude: venueLongitude,
			meetAt: meetAt,
			initialDistanceMeters: distance,
			now: now
		)
		return (snap, distance)
	}

	// MARK: - Private

	private static func travelETAMinutes(distance: CLLocationDistance, location: CLLocation) -> Int {
		let speed: CLLocationSpeed = {
			if location.speed >= 0.4 { return location.speed }
			return defaultWalkingSpeedMps
		}()
		guard speed > 0.05 else { return 0 }
		return max(0, Int(ceil(distance / speed / 60)))
	}

	private static func minutesUntil(_ date: Date, from now: Date) -> Int {
		max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
	}

	private static func formatMinutes(_ minutes: Int) -> String {
		if minutes <= 0 { return "Now" }
		if minutes < 60 { return "\(minutes) min" }
		let hours = minutes / 60
		let rem = minutes % 60
		return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
	}

	private static func formatDistance(_ meters: CLLocationDistance) -> String {
		if meters < 1000 {
			return "\(Int(meters.rounded())) m"
		}
		return String(format: "%.1f km", meters / 1000)
	}
}
