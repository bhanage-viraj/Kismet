import CoreLocation
import Testing
@testable import Kismet

struct PulseTargetingTests {
	@Test func availableIsEligible() {
		let card = card(presence: .available, reasons: [.nearbyWalk])
		#expect(PulseTargeting.isEligibleRecipient(for: card))
	}

	@Test func friendsOnlyIsEligible() {
		let card = card(presence: .friendsOnly, reasons: [.nearbyWalk])
		#expect(PulseTargeting.isEligibleRecipient(for: card))
	}

	@Test func approximateNeedsSharedInterest() {
		let without = card(presence: .approximate, reasons: [.nearbyWalk])
		#expect(!PulseTargeting.isEligibleRecipient(for: without))

		let withInterest = card(presence: .approximate, reasons: [.sharedInterest])
		#expect(PulseTargeting.isEligibleRecipient(for: withInterest))
	}

	@Test func eclipseNeverEligible() {
		let card = card(presence: .eclipse, reasons: [.sharedInterest])
		#expect(!PulseTargeting.isEligibleRecipient(for: card))
	}

	private func card(presence: PresenceState, reasons: [ExplainCode]) -> SuggestionCard {
		SuggestionCard(
			id: "c1",
			friendID: "f1",
			displayName: "Ada",
			coordinate: CLLocationCoordinate2D(latitude: 12.9, longitude: 77.6),
			availability: presence.mapAvailability,
			presence: presence,
			distanceMeters: 200,
			reason: "test",
			reasonCodes: reasons,
			factChips: [],
			ctaTitle: "Pulse",
			ctaSystemImage: "hand.wave",
			venueName: nil,
			venueETAMinutes: nil,
			confidence: 0.8,
			urgency: .now,
			isModelGenerated: false
		)
	}
}
