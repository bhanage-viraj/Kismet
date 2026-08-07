import CoreLocation
import Foundation
import Testing
@testable import Kismet

struct PulseVenuePayloadTests {
	private let venueCoordinate = CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.6412)
	private let liveGPS = CLLocationCoordinate2D(latitude: 12.9000, longitude: 77.5000)

	@Test func venueFieldsPreferSelectedMapKitVenue() {
		let selected = GroundedVenue(
			name: "Third Wave",
			coordinate: venueCoordinate,
			distanceMeters: 350,
			displayETALabel: "4 min walk",
			queryType: .coffee
		)
		var card = baseCard()
		card.selectedVenue = selected
		card.venueName = selected.name
		card.venueCoordinate = selected.coordinate
		// Even if card.coordinate were the user's live position, venue fields must use selectedVenue.
		card.coordinate = liveGPS

		let fields = PulseVenueFields.fromSuggestion(card)
		#expect(fields.name == "Third Wave")
		#expect(fields.latitude == venueCoordinate.latitude)
		#expect(fields.longitude == venueCoordinate.longitude)
		#expect(fields.latitude != liveGPS.latitude)
	}

	@Test func pulsePayloadRoundTripsVenueAndMessage() throws {
		let payload = PulsePayloadDTO(
			pulseId: "p1",
			emoji: "👋",
			label: "Send a Pulse",
			expiresAt: Date().addingTimeInterval(3600),
			venueName: "Third Wave",
			venueLatitude: venueCoordinate.latitude,
			venueLongitude: venueCoordinate.longitude,
			message: "Free to grab coffee?",
			createdAt: Date()
		)

		let data = try JSONEncoder().encode(payload)
		let decoded = try JSONDecoder().decode(PulsePayloadDTO.self, from: data)
		#expect(decoded.venueName == "Third Wave")
		#expect(decoded.message == "Free to grab coffee?")
		#expect(decoded.venueCoordinate?.latitude == venueCoordinate.latitude)
		#expect(decoded.venueCoordinate?.longitude == venueCoordinate.longitude)
	}

	@Test func meetupPayloadCopiesPulseVenuePinOnly() {
		let pulse = PulsePayloadDTO(
			pulseId: "p1",
			emoji: "👋",
			label: "Send a Pulse",
			expiresAt: Date().addingTimeInterval(3600),
			venueName: "Cubbon Park",
			venueLatitude: 12.97,
			venueLongitude: 77.59,
			message: "Free for a walk?",
			createdAt: Date()
		)
		let pin = MeetupPayloadDTO.venuePin(from: pulse)
		#expect(pin.name == "Cubbon Park")
		#expect(pin.latitude == 12.97)
		#expect(pin.longitude == 77.59)

		let meetup = MeetupPayloadDTO(
			meetupId: pulse.pulseId,
			title: pulse.label,
			venueName: pin.name,
			venueLatitude: pin.latitude,
			venueLongitude: pin.longitude,
			meetAt: pulse.expiresAt,
			peerDisplayName: "Ada",
			systemImage: "figure.walk",
			createdAt: Date()
		)
		#expect(meetup.venueCoordinate?.latitude == 12.97)
	}

	@Test func legacyPulseWithoutCoordsStillDecodes() throws {
		let json = """
		{
		  "pulseId": "old",
		  "emoji": "👋",
		  "label": "Send a Pulse",
		  "expiresAt": 0,
		  "venueName": "Cafe",
		  "createdAt": 0
		}
		""".data(using: .utf8)!
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .secondsSince1970
		let decoded = try decoder.decode(PulsePayloadDTO.self, from: json)
		#expect(decoded.venueName == "Cafe")
		#expect(decoded.venueLatitude == nil)
		#expect(decoded.message == nil)
		#expect(decoded.venueCoordinate == nil)
	}

	private func baseCard() -> SuggestionCard {
		SuggestionCard(
			id: "c1",
			friendID: "f1",
			displayName: "Ada",
			coordinate: liveGPS,
			availability: .free,
			presence: .available,
			distanceMeters: 200,
			reason: "test",
			reasonCodes: [.sharedInterest],
			factChips: [],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: nil,
			venueETAMinutes: nil,
			confidence: 0.8,
			urgency: .now,
			isModelGenerated: false
		)
	}
}
