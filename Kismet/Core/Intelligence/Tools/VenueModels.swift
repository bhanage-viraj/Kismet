import CoreLocation
import Foundation
import MapKit

/// Place-type signal used to search and score MapKit POIs.
enum VenueQueryType: String, Sendable, Hashable, CaseIterable {
	case coffee
	case restaurant
	case park
	case cafe
	case other

	var naturalLanguageQuery: String {
		switch self {
		case .coffee, .cafe: "coffee"
		case .restaurant: "restaurant"
		case .park: "park"
		case .other: "cafe"
		}
	}

	/// Map shared interest / usual_spot strings into a query type.
	static func infer(fromPlaceTypeSignal text: String?) -> VenueQueryType? {
		guard let text else { return nil }
		let lower = text.lowercased()
		if lower.contains("coffee") || lower.contains("cafe") || lower.contains("chai") {
			return .coffee
		}
		if lower.contains("food") || lower.contains("lunch") || lower.contains("dinner")
			|| lower.contains("restaurant") || lower.contains("brunch") {
			return .restaurant
		}
		if lower.contains("park") || lower.contains("walk") || lower.contains("nature")
			|| lower.contains("outdoor") {
			return .park
		}
		return nil
	}

	static func from(venueCategory: VenueCategory) -> VenueQueryType? {
		switch venueCategory {
		case .coffee: .coffee
		case .food: .restaurant
		case .walk: .park
		case .other: nil
		}
	}
}

/// Optional transport preference for **display** ETA labels only — never a hard filter.
enum VenueTransportPreference: String, Sendable, Hashable {
	case walking
	case automobile
	case transit

	var mapKitTransportType: MKDirectionsTransportType {
		switch self {
		case .walking: .walking
		case .automobile: .automobile
		case .transit: .transit
		}
	}
}

struct VenueQuery: Sendable {
	var type: VenueQueryType
	var origin: CLLocationCoordinate2D
	/// When set, ETA labels may be computed for display; never used to exclude venues.
	var transportPreference: VenueTransportPreference?

	init(
		type: VenueQueryType,
		origin: CLLocationCoordinate2D,
		transportPreference: VenueTransportPreference? = nil
	) {
		self.type = type
		self.origin = origin
		self.transportPreference = transportPreference
	}
}

/// Lightweight POI hit so ranking stays unit-testable without live MapKit.
struct VenueCandidateHit: Sendable, Hashable {
	var name: String
	var latitude: Double
	var longitude: Double
	var pointOfInterestCategory: MKPointOfInterestCategory?
	/// MapKit place id when available (Place Card / richer lookup).
	var mapItemIdentifier: String? = nil
	var phoneNumber: String? = nil
	var websiteURLString: String? = nil
	var addressSummary: String? = nil

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	/// Stronger business listing signal (phone / website) — useful when hours aren't exposed.
	var listingQualityScore: Int {
		var score = 0
		if phoneNumber?.isEmpty == false { score += 8 }
		if websiteURLString?.isEmpty == false { score += 8 }
		if mapItemIdentifier != nil { score += 4 }
		if addressSummary?.isEmpty == false { score += 2 }
		return score
	}

	init(
		name: String,
		coordinate: CLLocationCoordinate2D,
		pointOfInterestCategory: MKPointOfInterestCategory? = nil,
		mapItemIdentifier: String? = nil,
		phoneNumber: String? = nil,
		websiteURLString: String? = nil,
		addressSummary: String? = nil
	) {
		self.name = name
		self.latitude = coordinate.latitude
		self.longitude = coordinate.longitude
		self.pointOfInterestCategory = pointOfInterestCategory
		self.mapItemIdentifier = mapItemIdentifier
		self.phoneNumber = phoneNumber
		self.websiteURLString = websiteURLString
		self.addressSummary = addressSummary
	}

	init(mapItem: MKMapItem) {
		self.name = mapItem.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Place"
		let coord = mapItem.location.coordinate
		self.latitude = coord.latitude
		self.longitude = coord.longitude
		self.pointOfInterestCategory = mapItem.pointOfInterestCategory
		self.mapItemIdentifier = mapItem.identifier?.rawValue
		self.phoneNumber = mapItem.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
		self.websiteURLString = mapItem.url?.absoluteString
		self.addressSummary = mapItem.addressRepresentations?.cityName
			?? mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
	}
}

struct GroundedVenue: Sendable, Hashable, Identifiable {
	var id: String
	var name: String
	var latitude: Double
	var longitude: Double
	var distanceMeters: CLLocationDistance
	/// Informational only — never used as a filter.
	var displayETAMinutes: Int?
	/// e.g. "5 min walk", "8 min drive", "350 m"
	var displayETALabel: String?
	var queryType: VenueQueryType
	var mapItemIdentifier: String? = nil
	var phoneNumber: String? = nil
	var addressSummary: String? = nil
	/// Soft note from time-of-day / listing heuristics (not a hard open/closed claim).
	var suitabilityNote: String? = nil

	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	init(
		id: String = UUID().uuidString,
		name: String,
		coordinate: CLLocationCoordinate2D,
		distanceMeters: CLLocationDistance,
		displayETAMinutes: Int? = nil,
		displayETALabel: String? = nil,
		queryType: VenueQueryType,
		mapItemIdentifier: String? = nil,
		phoneNumber: String? = nil,
		addressSummary: String? = nil,
		suitabilityNote: String? = nil
	) {
		self.id = id
		self.name = name
		self.latitude = coordinate.latitude
		self.longitude = coordinate.longitude
		self.distanceMeters = distanceMeters
		self.displayETAMinutes = displayETAMinutes
		self.displayETALabel = displayETALabel
		self.queryType = queryType
		self.mapItemIdentifier = mapItemIdentifier
		self.phoneNumber = phoneNumber
		self.addressSummary = addressSummary
		self.suitabilityNote = suitabilityNote
	}
}

/// Ranked set for insights + optional Pulse compose picker.
struct GroundedVenueCandidates: Sendable, Hashable {
	var suggested: GroundedVenue
	var alternatives: [GroundedVenue]

	var all: [GroundedVenue] { [suggested] + alternatives }

	init(suggested: GroundedVenue, alternatives: [GroundedVenue] = []) {
		self.suggested = suggested
		self.alternatives = alternatives
	}

	/// Build from a ranked list (index 0 = suggested, next up to `maxAlternatives` = alternatives).
	static func fromRanked(_ ranked: [GroundedVenue], maxAlternatives: Int = 4) -> GroundedVenueCandidates? {
		guard let first = ranked.first else { return nil }
		let alts = Array(ranked.dropFirst().prefix(maxAlternatives))
		return GroundedVenueCandidates(suggested: first, alternatives: alts)
	}
}

/// Explicit venue UI/resolution state (Phase 1 wires this into cards).
enum VenueResolutionState: Sendable, Equatable {
	case loading
	case resolved(GroundedVenueCandidates)
	case empty
}

private extension String {
	var nilIfEmpty: String? {
		isEmpty ? nil : self
	}
}
