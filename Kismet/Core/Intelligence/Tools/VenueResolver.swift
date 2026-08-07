import CoreLocation
import Foundation
import MapKit

/// Deterministic MapKit venue ranking — distance/ETA are informational only (never a hard filter).
/// Uses POI category, time-of-day suitability, and available listing details (phone/URL/address).
/// Note: Apple does not expose opening hours as programmable data — Place Cards show hours to the user.
struct VenueResolver: Sendable {
	var searcher: any VenueSearching
	var cache: VenueResolutionCache
	var maxRawPool: Int
	var maxByRelevance: Int
	var maxAlternatives: Int

	init(
		searcher: any VenueSearching = NearbyVenueSearch(),
		cache: VenueResolutionCache = VenueResolutionCache(),
		maxRawPool: Int = 15,
		maxByRelevance: Int = 5,
		maxAlternatives: Int = 4
	) {
		self.searcher = searcher
		self.cache = cache
		self.maxRawPool = maxRawPool
		self.maxByRelevance = maxByRelevance
		self.maxAlternatives = maxAlternatives
	}

	/// Search (or cache hit) then rank into suggested + alternatives.
	func candidates(for query: VenueQuery, at now: Date = Date()) async throws -> GroundedVenueCandidates? {
		if let cached = cache.candidates(for: query) {
			return cached
		}

		let items = try await searcher.search(query: query)
		let hits = items.map(VenueCandidateHit.init(mapItem:))
		let resolved = Self.resolve(
			hits: hits,
			query: query,
			now: now,
			maxRawPool: maxRawPool,
			maxByRelevance: maxByRelevance,
			maxAlternatives: maxAlternatives
		)
		cache.store(resolved, for: query)
		return resolved
	}

	/// Pure ranking entry point for unit tests — no MapKit I/O.
	static func resolve(
		hits: [VenueCandidateHit],
		query: VenueQuery,
		now: Date = Date(),
		maxRawPool: Int = 15,
		maxByRelevance: Int = 5,
		maxAlternatives: Int = 4
	) -> GroundedVenueCandidates? {
		let pool = Array(hits.prefix(maxRawPool))
		guard !pool.isEmpty else { return nil }

		let timeBoost = timeSuitabilityScore(for: query.type, at: now)

		let scored = pool.map { hit -> (hit: VenueCandidateHit, score: Int, distance: CLLocationDistance) in
			let distance = CLLocation(latitude: query.origin.latitude, longitude: query.origin.longitude)
				.distance(from: CLLocation(latitude: hit.latitude, longitude: hit.longitude))
			let relevance = relevanceScore(category: hit.pointOfInterestCategory, for: query.type)
			let listing = hit.listingQualityScore
			// Soft demote places that look poor for this time of day (hours aren't available from MapKit).
			let score = relevance + listing + timeBoost
			return (hit, score, distance)
		}

		let byScore = scored
			.sorted { lhs, rhs in
				if lhs.score != rhs.score { return lhs.score > rhs.score }
				return lhs.distance < rhs.distance
			}
			.prefix(maxByRelevance)

		// Display order: nearest first within the score-capped set (not a hard distance filter).
		let byDistance = byScore.sorted { $0.distance < $1.distance }

		let grounded = byDistance.map { entry in
			makeGroundedVenue(hit: entry.hit, distance: entry.distance, query: query, now: now)
		}

		return GroundedVenueCandidates.fromRanked(grounded, maxAlternatives: maxAlternatives)
	}

	/// Convenience over `MKMapItem` arrays (production + tool bridge).
	static func resolve(
		candidates: [MKMapItem],
		query: VenueQuery,
		now: Date = Date(),
		maxRawPool: Int = 15,
		maxByRelevance: Int = 5,
		maxAlternatives: Int = 4
	) -> GroundedVenueCandidates? {
		resolve(
			hits: candidates.map(VenueCandidateHit.init(mapItem:)),
			query: query,
			now: now,
			maxRawPool: maxRawPool,
			maxByRelevance: maxByRelevance,
			maxAlternatives: maxAlternatives
		)
	}

	static func relevanceScore(
		category: MKPointOfInterestCategory?,
		for queryType: VenueQueryType
	) -> Int {
		guard let category else { return 10 }

		switch queryType {
		case .coffee, .cafe:
			switch category {
			case .cafe: return 100
			case .bakery: return 80
			case .restaurant: return 40
			case .store: return 25
			default: return 10
			}
		case .restaurant:
			switch category {
			case .restaurant: return 100
			case .cafe: return 70
			case .bakery: return 50
			case .store: return 20
			default: return 10
			}
		case .park:
			switch category {
			case .park: return 100
			case .nationalPark: return 95
			case .beach: return 80
			case .marina: return 50
			default: return 10
			}
		case .other:
			return 10
		}
	}

	/// Soft time-of-day prior when MapKit won't expose open/closed.
	/// Positive = prefer this place type now; negative = demote (often closed / dark / odd hours).
	static func timeSuitabilityScore(for queryType: VenueQueryType, at date: Date, calendar: Calendar = .current) -> Int {
		let hour = calendar.component(.hour, from: date)
		switch queryType {
		case .coffee, .cafe:
			if (7..<11).contains(hour) { return 25 }
			if (11..<17).contains(hour) { return 20 }
			if (17..<20).contains(hour) { return 5 }
			return -35
		case .restaurant:
			if (11..<14).contains(hour) { return 25 }
			if (18..<22).contains(hour) { return 25 }
			if (14..<18).contains(hour) { return 10 }
			if hour >= 22 || hour < 10 { return -30 }
			return 0
		case .park:
			if (7..<19).contains(hour) { return 20 }
			return -45
		case .other:
			if (8..<21).contains(hour) { return 5 }
			return -10
		}
	}

	static func suitabilityNote(for queryType: VenueQueryType, at date: Date, calendar: Calendar = .current) -> String? {
		let score = timeSuitabilityScore(for: queryType, at: date, calendar: calendar)
		guard score < 0 else { return nil }
		switch queryType {
		case .coffee, .cafe:
			return "Cafés are often closed this late"
		case .restaurant:
			return "Outside typical meal hours"
		case .park:
			return "Parks are better in daylight"
		case .other:
			return "Unusual time for this spot"
		}
	}

	private static func makeGroundedVenue(
		hit: VenueCandidateHit,
		distance: CLLocationDistance,
		query: VenueQuery,
		now: Date
	) -> GroundedVenue {
		let eta = displayETA(distanceMeters: distance, preference: query.transportPreference)
		return GroundedVenue(
			id: "\(hit.name)|\(hit.latitude)|\(hit.longitude)",
			name: hit.name,
			coordinate: hit.coordinate,
			distanceMeters: distance,
			displayETAMinutes: eta.minutes,
			displayETALabel: eta.label,
			queryType: query.type,
			mapItemIdentifier: hit.mapItemIdentifier,
			phoneNumber: hit.phoneNumber,
			addressSummary: hit.addressSummary,
			suitabilityNote: suitabilityNote(for: query.type, at: now)
		)
	}

	/// Straight-line heuristics for labels — informational only.
	static func displayETA(
		distanceMeters: CLLocationDistance,
		preference: VenueTransportPreference?
	) -> (minutes: Int?, label: String) {
		switch preference {
		case .walking:
			let minutes = max(1, Int((distanceMeters / 80).rounded()))
			return (minutes, "\(minutes) min walk")
		case .automobile:
			let minutes = max(1, Int((distanceMeters / 500).rounded()))
			return (minutes, "\(minutes) min drive")
		case .transit:
			let minutes = max(1, Int((distanceMeters / 250).rounded()))
			return (minutes, "\(minutes) min transit")
		case nil:
			if distanceMeters < 1_000 {
				return (nil, "\(Int(distanceMeters.rounded())) m")
			}
			let km = distanceMeters / 1_000
			return (nil, String(format: "%.1f km", km))
		}
	}
}

/// In-memory cache: (queryType, ~100m coordinate bucket) → candidates, TTL 15 minutes.
final class VenueResolutionCache: @unchecked Sendable {
	struct Key: Hashable, Sendable {
		var type: VenueQueryType
		var searchText: String
		var latBucket: Int
		var lonBucket: Int
	}

	private struct Entry {
		var candidates: GroundedVenueCandidates?
		var storedAt: Date
	}

	private let lock = NSLock()
	private var storage: [Key: Entry] = [:]
	var ttl: TimeInterval

	/// ~100m at equator ≈ 0.0009 degrees.
	var bucketDegrees: Double

	init(ttl: TimeInterval = 15 * 60, bucketDegrees: Double = 0.0009) {
		self.ttl = ttl
		self.bucketDegrees = bucketDegrees
	}

	func key(for query: VenueQuery) -> Key {
		Key(
			type: query.type,
			searchText: query.searchText,
			latBucket: Int((query.origin.latitude / bucketDegrees).rounded(.towardZero)),
			lonBucket: Int((query.origin.longitude / bucketDegrees).rounded(.towardZero))
		)
	}

	func candidates(for query: VenueQuery) -> GroundedVenueCandidates? {
		lock.lock()
		defer { lock.unlock() }
		let k = key(for: query)
		guard let entry = storage[k] else { return nil }
		guard Date().timeIntervalSince(entry.storedAt) < ttl else {
			storage.removeValue(forKey: k)
			return nil
		}
		return entry.candidates
	}

	func store(_ candidates: GroundedVenueCandidates?, for query: VenueQuery) {
		lock.lock()
		defer { lock.unlock() }
		storage[key(for: query)] = Entry(candidates: candidates, storedAt: Date())
	}

	func clear() {
		lock.lock()
		defer { lock.unlock() }
		storage.removeAll()
	}
}
