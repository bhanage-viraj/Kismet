import CoreLocation
import Foundation
import Testing
@testable import Kismet

struct PulseMessageComposerTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.93, longitude: 77.62)

	private func venue(_ name: String, type: VenueQueryType) -> GroundedVenue {
		GroundedVenue(
			name: name,
			coordinate: origin,
			distanceMeters: 180,
			queryType: type
		)
	}

	private func hints(
		interests: [String] = ["coffee"],
		codes: [ExplainCode] = [.bothFree, .goodTimeForCoffee],
		pastMeetups: Int = 0,
		preferred: VenueCategory? = nil,
		time: PulseTimeOfDay = .afternoon,
		motion: MotionActivityKind = .stationary,
		friendFreeUntil: Date? = nil,
		weather: WeatherConditionKind = .unknown,
		usual: Bool = false
	) -> PulseDraftHints {
		PulseDraftHints(
			sharedInterests: interests,
			reasonCodes: codes,
			pastMeetupCount: pastMeetups,
			preferredCategory: preferred,
			timeOfDay: time,
			motion: motion,
			freeUntil: nil,
			friendFreeUntil: friendFreeUntil,
			weather: weather,
			isUsualMeetupTime: usual
		)
	}

	@Test func coffeeVenueIncludesPlaceName() {
		let message = PulseMessageComposer.draft(
			venue: venue("Third Wave Coffee", type: .coffee),
			hints: hints()
		)
		#expect(message.localizedCaseInsensitiveContains("Third Wave Coffee"))
		#expect(message.localizedCaseInsensitiveContains("coffee"))
	}

	@Test func pastMeetupPrefersAgainFraming() {
		let message = PulseMessageComposer.draft(
			venue: venue("Third Wave Coffee", type: .coffee),
			hints: hints(pastMeetups: 3, preferred: .coffee)
		)
		#expect(message == "Coffee at Third Wave Coffee again?")
	}

	@Test func rainyWeatherSteersIndoor() {
		let message = PulseMessageComposer.draft(
			venue: venue("Cubbon Park", type: .park),
			hints: hints(interests: ["walk"], codes: [.nearbyWalk], weather: .rain)
		)
		#expect(message.localizedCaseInsensitiveContains("wet") || message.localizedCaseInsensitiveContains("indoors"))
	}

	@Test func clearWeatherParkIsSunnyFramed() {
		let message = PulseMessageComposer.draft(
			venue: venue("Cubbon Park", type: .park),
			hints: hints(interests: ["walk"], codes: [.nearbyWalk], weather: .clear)
		)
		#expect(message == "Nice out — walk at Cubbon Park?")
	}

	@Test func sharedInterestFraming() {
		let message = PulseMessageComposer.draft(
			venue: venue("Blue Tokai", type: .coffee),
			hints: hints(interests: ["coffee"], weather: .cloudy)
		)
		#expect(message.localizedCaseInsensitiveContains("coffee"))
		#expect(message.localizedCaseInsensitiveContains("Blue Tokai"))
	}

	@Test func freeUntilAddsBeforeWindow() {
		let until = Date().addingTimeInterval(90 * 60)
		let message = PulseMessageComposer.draft(
			venue: venue("Third Wave Coffee", type: .coffee),
			hints: hints(friendFreeUntil: until, weather: .cloudy)
		)
		#expect(message.localizedCaseInsensitiveContains("before"))
	}

	@Test func middayRestaurantBecomesLunch() {
		let message = PulseMessageComposer.draft(
			venue: venue("Toit", type: .restaurant),
			hints: hints(
				interests: ["food"],
				codes: [.sharedInterest],
				time: .midday,
				weather: .cloudy
			)
		)
		#expect(message.localizedCaseInsensitiveContains("lunch"))
		#expect(message.localizedCaseInsensitiveContains("Toit"))
	}

	@Test func switchingVenueRewritesDraft() {
		let coffee = venue("Third Wave Coffee", type: .coffee)
		let park = venue("Cubbon Park", type: .park)
		let h = hints(weather: .clear)
		let first = PulseMessageComposer.draft(venue: coffee, hints: h)
		let second = PulseMessageComposer.draft(updatingFrom: first, venue: park, hints: h)
		#expect(first.localizedCaseInsensitiveContains("Third Wave"))
		#expect(second == "Nice out — walk at Cubbon Park?")
	}

	@Test func selectVenueUpdatesCardPulseMessage() {
		var card = SuggestionCard(
			id: "ada",
			friendID: "ada",
			displayName: "Ada",
			coordinate: origin,
			availability: .free,
			presence: .available,
			distanceMeters: 200,
			reason: "Both free",
			reasonCodes: [.bothFree, .goodTimeForCoffee],
			factChips: [],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: "Third Wave Coffee",
			venueETAMinutes: 2,
			confidence: 0.8,
			urgency: .now,
			isModelGenerated: false,
			pulseMessage: "Afternoon free — free to grab coffee at Third Wave Coffee?",
			draftHints: hints(weather: .cloudy)
		)
		card.selectVenue(venue("Blue Tokai", type: .coffee))
		#expect(card.venueName == "Blue Tokai")
		#expect(card.pulseMessage?.localizedCaseInsensitiveContains("Blue Tokai") == true)
	}

	@Test func sameInputsAreStable() {
		let v = venue("Matteo Coffea", type: .coffee)
		let h = hints(weather: .cloudy)
		#expect(PulseMessageComposer.draft(venue: v, hints: h) == PulseMessageComposer.draft(venue: v, hints: h))
	}

	@Test func noVenueFallsBackByReasonCode() {
		let message = PulseMessageComposer.draft(
			venue: nil,
			hints: hints(weather: .unknown)
		)
		#expect(message.localizedCaseInsensitiveContains("coffee"))
	}
}
