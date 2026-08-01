import CoreLocation
import Foundation

enum MockFriendsProvider {
	/// Demo seed centered on Koramangala when the device has no fix yet (Simulator-friendly).
	static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	private struct Seed {
		let id: String
		let displayName: String
		let availability: MapAvailability
		let eastMeters: Double
		let northMeters: Double
		let insightSummary: String
		let intentLabel: String
		let neighborhoodLabel: String
		let mutualFriendCount: Int
		let accentSystemImage: String
		let ctaTitle: String
		let ctaSystemImage: String
	}

	private static let seeds: [Seed] = [
		Seed(
			id: "mock-alex",
			displayName: "Alex",
			availability: .free,
			eastMeters: -45,
			northMeters: 55,
			insightSummary: "Just finished a meeting.\nFree until 3:00 PM. 5 mins away.",
			intentLabel: "Free to hang • Coffee",
			neighborhoodLabel: "Near Koramangala 5th Block",
			mutualFriendCount: 6,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: "Send APNS Catch Up Ping",
			ctaSystemImage: "bolt.fill"
		),
		Seed(
			id: "mock-sam",
			displayName: "Sam",
			availability: .busy,
			eastMeters: 70,
			northMeters: 40,
			insightSummary: "Deep work ending in 10 mins.\n12 mins away.",
			intentLabel: "Deep work • Back soon",
			neighborhoodLabel: "Near Koramangala 4th Block",
			mutualFriendCount: 4,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: "Ping when free",
			ctaSystemImage: "hourglass"
		),
		Seed(
			id: "mock-ishita",
			displayName: "Ishita",
			availability: .unknown,
			eastMeters: -60,
			northMeters: -35,
			insightSummary: "Around the corner — status unclear. 8 mins away.",
			intentLabel: "Nearby • Open to plans",
			neighborhoodLabel: "Near Koramangala 6th Block",
			mutualFriendCount: 3,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: "Say hi nearby",
			ctaSystemImage: "hand.wave.fill"
		),
		Seed(
			id: "mock-rohan",
			displayName: "Rohan",
			availability: .busy,
			eastMeters: 50,
			northMeters: -50,
			insightSummary: "Wrapping up a call. Free after 4:00 PM. 15 mins away.",
			intentLabel: "Busy • Coffee later",
			neighborhoodLabel: "Near Sony World Signal",
			mutualFriendCount: 5,
			accentSystemImage: "person.crop.circle.fill",
			ctaTitle: "Ping when free",
			ctaSystemImage: "hourglass"
		),
	]

	static func friends(around origin: CLLocationCoordinate2D) -> [MapPerson] {
		seeds.map { seed in
			let coordinate = offset(
				from: origin,
				eastMeters: seed.eastMeters,
				northMeters: seed.northMeters
			)
			let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
				.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))

			return MapPerson(
				id: seed.id,
				displayName: seed.displayName,
				coordinate: coordinate,
				availability: seed.availability,
				distanceMeters: distance,
				insightSummary: seed.insightSummary,
				intentLabel: seed.intentLabel,
				neighborhoodLabel: seed.neighborhoodLabel,
				mutualFriendCount: seed.mutualFriendCount,
				accentSystemImage: seed.accentSystemImage,
				ctaTitle: seed.ctaTitle,
				ctaSystemImage: seed.ctaSystemImage
			)
		}
	}

	/// Rough meters → lat/lon offset suitable for city-block mock distances.
	static func offset(
		from origin: CLLocationCoordinate2D,
		eastMeters: Double,
		northMeters: Double
	) -> CLLocationCoordinate2D {
		let metersPerDegreeLat = 111_320.0
		let metersPerDegreeLon = 111_320.0 * cos(origin.latitude * .pi / 180)
		let dLat = northMeters / metersPerDegreeLat
		let dLon = eastMeters / max(metersPerDegreeLon, 1)
		return CLLocationCoordinate2D(
			latitude: origin.latitude + dLat,
			longitude: origin.longitude + dLon
		)
	}
}
