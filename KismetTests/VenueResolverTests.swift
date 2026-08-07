import CoreLocation
import Foundation
import MapKit
import Testing
@testable import Kismet

struct VenueResolverTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)

	@Test func emptyHitsReturnNil() {
		let query = VenueQuery(type: .coffee, origin: origin)
		let result = VenueResolver.resolve(hits: [], query: query)
		#expect(result == nil)
	}

	@Test func suggestedIsNearestAmongTopRelevance() {
		let query = VenueQuery(type: .coffee, origin: origin)
		let hits = [
			VenueCandidateHit(name: "Far Cafe", coordinate: offset(origin, metersNorth: 800, metersEast: 0), pointOfInterestCategory: .cafe),
			VenueCandidateHit(name: "Near Cafe", coordinate: offset(origin, metersNorth: 100, metersEast: 0), pointOfInterestCategory: .cafe),
			VenueCandidateHit(name: "Mid Cafe", coordinate: offset(origin, metersNorth: 400, metersEast: 0), pointOfInterestCategory: .cafe)
		]

		let result = VenueResolver.resolve(hits: hits, query: query)
		#expect(result?.suggested.name == "Near Cafe")
		#expect(result?.alternatives.map(\.name) == ["Mid Cafe", "Far Cafe"])
	}

	@Test func relevanceBeatsDistanceWhenCappingPool() {
		// Many low-relevance stores nearby; a cafe farther away must still enter the top-5 by relevance,
		// then display order sorts by distance within that set.
		let query = VenueQuery(type: .coffee, origin: origin)
		var hits: [VenueCandidateHit] = (0..<10).map { index in
			VenueCandidateHit(
				name: "Store \(index)",
				coordinate: offset(origin, metersNorth: Double(20 + index * 5), metersEast: 0),
				pointOfInterestCategory: .store
			)
		}
		hits.append(
			VenueCandidateHit(
				name: "Real Cafe",
				coordinate: offset(origin, metersNorth: 600, metersEast: 0),
				pointOfInterestCategory: .cafe
			)
		)

		let result = VenueResolver.resolve(hits: hits, query: query, maxRawPool: 15, maxByRelevance: 5)
		#expect(result?.all.contains(where: { $0.name == "Real Cafe" }) == true)
		#expect(result?.suggested.name == "Real Cafe" || result?.alternatives.contains(where: { $0.name == "Real Cafe" }) == true)
	}

	@Test func farHighRelevanceVenueIsNotExcluded() {
		let query = VenueQuery(type: .restaurant, origin: origin)
		let hits = [
			VenueCandidateHit(
				name: "Favorite Spot Across Town",
				coordinate: offset(origin, metersNorth: 4_000, metersEast: 0),
				pointOfInterestCategory: .restaurant
			),
			VenueCandidateHit(
				name: "Nearby Diner",
				coordinate: offset(origin, metersNorth: 200, metersEast: 0),
				pointOfInterestCategory: .restaurant
			)
		]

		let result = VenueResolver.resolve(hits: hits, query: query)
		#expect(result?.all.count == 2)
		#expect(result?.all.contains(where: { $0.name == "Favorite Spot Across Town" }) == true)
		// Display order: nearest first
		#expect(result?.suggested.name == "Nearby Diner")
		#expect(result?.alternatives.first?.name == "Favorite Spot Across Town")
	}

	@Test func candidatesShapeSuggestedPlusAlternatives() {
		let query = VenueQuery(type: .park, origin: origin)
		let hits = (0..<6).map { index in
			VenueCandidateHit(
				name: "Park \(index)",
				coordinate: offset(origin, metersNorth: Double(100 * (index + 1)), metersEast: 0),
				pointOfInterestCategory: .park
			)
		}

		let result = VenueResolver.resolve(hits: hits, query: query, maxAlternatives: 4)
		#expect(result != nil)
		#expect(result?.suggested.name == "Park 0")
		#expect(result?.alternatives.count == 4)
		#expect(result?.all.count == 5)
	}

	@Test func walkingPreferenceAddsDisplayETANotFilter() {
		let query = VenueQuery(type: .coffee, origin: origin, transportPreference: .walking)
		let hits = [
			VenueCandidateHit(
				name: "Cafe",
				coordinate: offset(origin, metersNorth: 400, metersEast: 0),
				pointOfInterestCategory: .cafe
			)
		]

		let result = VenueResolver.resolve(hits: hits, query: query)
		#expect(result?.suggested.displayETAMinutes != nil)
		#expect(result?.suggested.displayETALabel?.contains("walk") == true)
	}

	@Test func nilTransportShowsDistanceLabel() {
		let query = VenueQuery(type: .coffee, origin: origin, transportPreference: nil)
		let hits = [
			VenueCandidateHit(
				name: "Cafe",
				coordinate: offset(origin, metersNorth: 350, metersEast: 0),
				pointOfInterestCategory: .cafe
			)
		]

		let result = VenueResolver.resolve(hits: hits, query: query)
		#expect(result?.suggested.displayETAMinutes == nil)
		#expect(result?.suggested.displayETALabel?.contains("m") == true)
	}

	@Test func cacheReturnsStoredCandidates() async throws {
		let query = VenueQuery(type: .coffee, origin: origin)
		let item = makeMapItem(
			name: "Cached Cafe",
			coordinate: offset(origin, metersNorth: 120, metersEast: 0),
			category: .cafe
		)
		let cache = VenueResolutionCache()
		let resolver = VenueResolver(searcher: MockVenueSearch(items: [item]), cache: cache)

		let first = try await resolver.candidates(for: query)
		#expect(first?.suggested.name == "Cached Cafe")

		// Empty searcher would fail if cache missed.
		let resolverCached = VenueResolver(searcher: MockVenueSearch(items: []), cache: cache)
		let second = try await resolverCached.candidates(for: query)
		#expect(second?.suggested.name == "Cached Cafe")
	}

	@Test func queryTypeInferFromSignals() {
		#expect(VenueQueryType.infer(fromPlaceTypeSignal: "Both like coffee") == .coffee)
		#expect(VenueQueryType.infer(fromPlaceTypeSignal: "lunch") == .restaurant)
		#expect(VenueQueryType.infer(fromPlaceTypeSignal: "park walk") == .park)
		#expect(VenueQueryType.infer(fromPlaceTypeSignal: "chess") == nil)
	}

	@Test func relevanceScoresPreferMatchingCategory() {
		#expect(VenueResolver.relevanceScore(category: .cafe, for: .coffee) >
			VenueResolver.relevanceScore(category: .restaurant, for: .coffee))
		#expect(VenueResolver.relevanceScore(category: .park, for: .park) >
			VenueResolver.relevanceScore(category: .cafe, for: .park))
	}

	@Test func lateNightDemotesCoffeeCandidates() {
		var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
		components.hour = 23
		components.minute = 0
		let late = Calendar.current.date(from: components) ?? Date()

		#expect(VenueResolver.timeSuitabilityScore(for: .coffee, at: late) < 0)
		#expect(VenueResolver.suitabilityNote(for: .coffee, at: late) != nil)
	}

	@Test func middayBoostsRestaurantCandidates() {
		var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
		components.hour = 12
		components.minute = 30
		let noon = Calendar.current.date(from: components) ?? Date()

		#expect(VenueResolver.timeSuitabilityScore(for: .restaurant, at: noon) > 0)
	}

	@Test func listingQualityPrefersPhoneAndURL() {
		let bare = VenueCandidateHit(
			name: "Bare Cafe",
			coordinate: origin,
			pointOfInterestCategory: .cafe
		)
		let rich = VenueCandidateHit(
			name: "Listed Cafe",
			coordinate: origin,
			pointOfInterestCategory: .cafe,
			phoneNumber: "+91 12345",
			websiteURLString: "https://example.com"
		)
		#expect(rich.listingQualityScore > bare.listingQualityScore)
	}

	// MARK: - Helpers

	private func offset(
		_ origin: CLLocationCoordinate2D,
		metersNorth: Double,
		metersEast: Double
	) -> CLLocationCoordinate2D {
		let metersPerDegreeLat = 111_320.0
		let metersPerDegreeLon = 111_320.0 * cos(origin.latitude * .pi / 180)
		return CLLocationCoordinate2D(
			latitude: origin.latitude + metersNorth / metersPerDegreeLat,
			longitude: origin.longitude + metersEast / metersPerDegreeLon
		)
	}

	private func makeMapItem(
		name: String,
		coordinate: CLLocationCoordinate2D,
		category: MKPointOfInterestCategory
	) -> MKMapItem {
		let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
		item.name = name
		item.pointOfInterestCategory = category
		return item
	}
}
