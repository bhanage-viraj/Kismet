import CoreLocation
import Foundation

/// Derives a place-type query from ranking signals, and merges resolver vs model venue fields.
enum VenueGrounding {
	/// Infer a MapKit query type from shared interests, usual spot, or time-of-day coffee signal.
	static func queryType(for item: RankedOpportunity) -> VenueQueryType? {
		for interest in item.friend.sharedInterests {
			if let type = VenueQueryType.infer(fromPlaceTypeSignal: interest) {
				return type
			}
		}

		if let category = item.learnedStats?.preferredCategories.first,
		   let type = VenueQueryType.from(venueCategory: category) {
			return type
		}

		if item.reasonCodes.contains(.goodTimeForCoffee) {
			return .coffee
		}

		return nil
	}

	/// Suggested Pulse activity for compose, derived from the same signals used for venue grounding.
	static func suggestedActivity(for item: RankedOpportunity) -> PulseActivity {
		switch queryType(for: item) {
		case .coffee, .cafe: return .coffee
		case .park: return .walk
		case .restaurant: return .coffee
		case .other: return .more
		case .none: return .more
		}
	}

	static func activityCandidates(for item: RankedOpportunity) -> GroundedActivityCandidates {
		let suggested = suggestedActivity(for: item)
		let alternatives = PulseActivity.allCases.filter { $0 != suggested && $0 != .more }
		return GroundedActivityCandidates(suggested: suggested, alternatives: Array(alternatives.prefix(3)))
	}

	/// Resolve venues for a compose activity near an origin (used when the user switches activity chips).
	static func resolve(
		activity: PulseActivity,
		origin: CLLocationCoordinate2D,
		resolver: VenueResolver = VenueResolver()
	) async -> GroundedVenueCandidates? {
		let type = VenueQueryType.from(pulseActivity: activity)
		let query = VenueQuery(
			type: type,
			origin: origin,
			transportPreference: .walking,
			naturalLanguageOverride: VenueQueryType.searchQuery(for: activity)
		)
		do {
			return try await resolver.candidates(for: query)
		} catch {
			return nil
		}
	}

	static func query(
		for item: RankedOpportunity,
		origin: CLLocationCoordinate2D,
		transportPreference: VenueTransportPreference? = .walking
	) -> VenueQuery? {
		guard let type = queryType(for: item) else { return nil }
		return VenueQuery(type: type, origin: origin, transportPreference: transportPreference)
	}

	/// Resolve venues for each ranked opportunity (uses cache inside `VenueResolver`).
	static func resolveStates(
		for ranked: [RankedOpportunity],
		origin: CLLocationCoordinate2D,
		resolver: VenueResolver
	) async -> [String: VenueResolutionState] {
		var result: [String: VenueResolutionState] = [:]
		await withTaskGroup(of: (String, VenueResolutionState).self) { group in
			for item in ranked {
				group.addTask {
					guard let query = query(for: item, origin: origin) else {
						return (item.friend.id, .empty)
					}
					do {
						if let candidates = try await resolver.candidates(for: query) {
							return (item.friend.id, .resolved(candidates))
						}
						return (item.friend.id, .empty)
					} catch {
						return (item.friend.id, .empty)
					}
				}
			}
			for await (friendID, state) in group {
				result[friendID] = state
			}
		}
		return result
	}

	/// 3-state merge: VenueResolver wins; never use model-invented venue names.
	static func mergeVenue(
		resolverState: VenueResolutionState?,
		modelVenueName: String?,
		modelVenueETAMinutes: Int?
	) -> MergedVenueFields {
		_ = modelVenueName
		_ = modelVenueETAMinutes

		switch resolverState {
		case .resolved(let candidates):
			let suggested = candidates.suggested
			return MergedVenueFields(
				resolution: .resolved(candidates),
				selectedVenue: suggested,
				venueName: suggested.name,
				venueETAMinutes: suggested.displayETAMinutes,
				venueCoordinate: suggested.coordinate,
				displayETALabel: suggested.displayETALabel
			)
		case .loading:
			return MergedVenueFields(
				resolution: .loading,
				selectedVenue: nil,
				venueName: nil,
				venueETAMinutes: nil,
				venueCoordinate: nil,
				displayETALabel: nil
			)
		case .empty, .none:
			// Priority 2 (FM tool) is not structured into merge yet; priority 3 (invented) is discarded.
			return MergedVenueFields(
				resolution: .empty,
				selectedVenue: nil,
				venueName: nil,
				venueETAMinutes: nil,
				venueCoordinate: nil,
				displayETALabel: nil
			)
		}
	}
}

struct MergedVenueFields: Sendable {
	var resolution: VenueResolutionState
	var selectedVenue: GroundedVenue?
	var venueName: String?
	var venueETAMinutes: Int?
	var venueCoordinate: CLLocationCoordinate2D?
	var displayETALabel: String?
}
