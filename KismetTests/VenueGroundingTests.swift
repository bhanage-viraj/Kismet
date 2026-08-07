import CoreLocation
import Foundation
import MapKit
import Testing
@testable import Kismet

struct VenueGroundingTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)

	@Test func queryTypeFromSharedCoffeeInterest() {
		let item = ranked(
			shared: ["Coffee"],
			codes: [.sharedInterest],
			usual: nil
		)
		#expect(VenueGrounding.queryType(for: item) == .coffee)
	}

	@Test func queryTypeFromUsualSpotFood() {
		let item = ranked(
			shared: [],
			codes: [.pastHangouts],
			usual: .food
		)
		#expect(VenueGrounding.queryType(for: item) == .restaurant)
	}

	@Test func queryTypeFromCoffeeReasonCode() {
		let item = ranked(
			shared: [],
			codes: [.goodTimeForCoffee],
			usual: nil
		)
		#expect(VenueGrounding.queryType(for: item) == .coffee)
	}

	@Test func queryTypeNilWithoutPlaceSignal() {
		let item = ranked(
			shared: [],
			codes: [.nearbyWalk, .bothFree],
			usual: nil
		)
		#expect(VenueGrounding.queryType(for: item) == nil)
	}

	@Test func mergePrefersResolverOverModelInventedName() {
		let suggested = GroundedVenue(
			name: "Blue Tokai",
			coordinate: origin,
			distanceMeters: 200,
			displayETAMinutes: 3,
			displayETALabel: "3 min walk",
			queryType: .coffee
		)
		let candidates = GroundedVenueCandidates(suggested: suggested, alternatives: [])
		let merged = VenueGrounding.mergeVenue(
			resolverState: .resolved(candidates),
			modelVenueName: "Totally Fake Cafe",
			modelVenueETAMinutes: 99
		)
		#expect(merged.venueName == "Blue Tokai")
		#expect(merged.venueETAMinutes == 3)
		#expect(merged.selectedVenue?.name == "Blue Tokai")
		if case .resolved(let c) = merged.resolution {
			#expect(c.suggested.name == "Blue Tokai")
		} else {
			Issue.record("Expected resolved venue state")
		}
	}

	@Test func mergeDiscardsModelVenueWhenResolverEmpty() {
		let merged = VenueGrounding.mergeVenue(
			resolverState: .empty,
			modelVenueName: "Invented Spot",
			modelVenueETAMinutes: 5
		)
		#expect(merged.venueName == nil)
		#expect(merged.venueETAMinutes == nil)
		#expect(merged.resolution == .empty)
	}

	@Test func fallbackChipsNearbyOptionsWhenAlternativesExist() {
		let suggested = GroundedVenue(
			name: "A",
			coordinate: origin,
			distanceMeters: 100,
			queryType: .coffee
		)
		let alt = GroundedVenue(
			name: "B",
			coordinate: offset(origin, metersNorth: 200, metersEast: 0),
			distanceMeters: 200,
			queryType: .coffee
		)
		let venue = VenueGrounding.mergeVenue(
			resolverState: .resolved(GroundedVenueCandidates(suggested: suggested, alternatives: [alt])),
			modelVenueName: nil,
			modelVenueETAMinutes: nil
		)
		let item = ranked(shared: ["coffee"], codes: [.sharedInterest], usual: nil)
		let chips = FallbackComposer.factChips(for: item, venue: venue)
		#expect(chips.contains("Nearby options available"))
	}

	@Test func fallbackOmitsVenueChipWhenEmpty() {
		let venue = VenueGrounding.mergeVenue(
			resolverState: .empty,
			modelVenueName: nil,
			modelVenueETAMinutes: nil
		)
		let item = ranked(shared: [], codes: [.nearbyWalk], usual: nil)
		let chips = FallbackComposer.factChips(for: item, venue: venue)
		#expect(!chips.contains(where: { $0.localizedCaseInsensitiveContains("meet at") }))
		#expect(!chips.contains("Nearby options available"))
	}

	@Test func promptIncludesGroundedVenueAndAgnosticInstructions() {
		let friend = FriendPresence(
			id: "f1",
			displayName: "Ada",
			coordinate: origin,
			presence: .available,
			distanceMeters: 150,
			sharedInterests: ["coffee"]
		)
		let ranked = [
			RankedOpportunity(friend: friend, score: 2, reasonCodes: [.sharedInterest, .bothFree], learnedStats: nil)
		]
		let suggested = GroundedVenue(
			name: "Third Wave",
			coordinate: origin,
			distanceMeters: 150,
			displayETALabel: "2 min walk",
			queryType: .coffee
		)
		let states: [String: VenueResolutionState] = [
			"f1": .resolved(GroundedVenueCandidates(suggested: suggested))
		]
		let context = KismetContext(
			generatedAt: Date(),
			user: UserContextSlice(
				userId: "u1",
				displayName: "You",
				interests: ["coffee"],
				coordinate: origin,
				placeName: nil,
				freeUntil: nil,
				isBusyNow: false
			),
			friends: [friend],
			calendar: CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: nil),
			motion: MotionSlice(activity: .walking),
			focus: FocusSlice(blocksSocial: false, label: nil),
			weather: .unknown,
			learned: .empty
		)
		let prompt = PromptBuilder.prompt(context: context, ranked: ranked, venueStates: states)
		#expect(prompt.contains("grounded_venue=Third Wave"))
		#expect(prompt.contains("Leave venueName"))
		#expect(prompt.contains("pulseMessage empty") || PromptBuilder.instructions.contains("pulseMessage empty"))
	}

	// MARK: - Helpers

	private func ranked(
		shared: [String],
		codes: [ExplainCode],
		usual: VenueCategory?
	) -> RankedOpportunity {
		let friend = FriendPresence(
			id: "friend",
			displayName: "Sam",
			coordinate: origin,
			presence: .available,
			distanceMeters: 200,
			sharedInterests: shared
		)
		let stats: FriendLearnedStats? = {
			guard let usual else { return nil }
			return FriendLearnedStats(
				friendUserId: "friend",
				friendDisplayName: "Sam",
				completedCount: 2,
				affinityScore: 0.5,
				hoursSinceLastCompletedMeetup: 48,
				dismissCount: 0,
				ctaCount: 0,
				upCount: 0,
				downCount: 0,
				preferredCategories: [usual]
			)
		}()
		return RankedOpportunity(
			friend: friend,
			score: 1.5,
			reasonCodes: codes,
			learnedStats: stats
		)
	}

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
}
