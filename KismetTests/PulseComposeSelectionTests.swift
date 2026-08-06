import CoreLocation
import Testing
@testable import Kismet

struct PulseComposeSelectionTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.93, longitude: 77.62)

	@Test func defaultsToSuggested() {
		let selection = PulseComposeSelection(candidates: sampleCandidates())
		#expect(selection.isUsingSuggested)
		#expect(selection.lockedVenue().name == "Third Wave Coffee")
		#expect(selection.selectedID == selection.suggested.id)
	}

	@Test func selectingAlternativeOverridesSuggested() {
		var selection = PulseComposeSelection(candidates: sampleCandidates())
		let alt = sampleCandidates().alternatives[0]
		selection.select(alt)
		#expect(!selection.isUsingSuggested)
		#expect(selection.lockedVenue().id == alt.id)
		#expect(selection.lockedVenue().name == "Blue Tokai")
	}

	@Test func suggestedStaysMarkedInCandidatesAfterOverride() {
		var selection = PulseComposeSelection(candidates: sampleCandidates())
		selection.select(sampleCandidates().alternatives[1])
		#expect(selection.candidates.suggested.name == "Third Wave Coffee")
		#expect(selection.selected.name == "Matteo Coffea")
	}

	@Test func ignorePickerDefaultsToSuggestedAtSend() {
		// Mimics dismiss/ignore: never call select — locked venue is still suggested.
		let selection = PulseComposeSelection(candidates: sampleCandidates())
		var card = PulseComposePreviewData.card
		card.selectVenue(selection.lockedVenue())
		#expect(card.venueName == "Third Wave Coffee")
		#expect(card.selectedVenue?.id == selection.suggested.id)
	}

	@Test func pulseMessageUpdatesWhenVenueSwitches() {
		var card = PulseComposePreviewData.card
		card.draftHints = PulseDraftHints(
			sharedInterests: ["coffee"],
			reasonCodes: [.bothFree, .goodTimeForCoffee],
			pastMeetupCount: 0,
			preferredCategory: .coffee,
			timeOfDay: .afternoon,
			motion: .stationary,
			freeUntil: nil,
			friendFreeUntil: nil,
			weather: .cloudy,
			isUsualMeetupTime: false
		)
		var selection = PulseComposeSelection(candidates: sampleCandidates())
		selection.select(sampleCandidates().alternatives[0])
		card.selectVenue(selection.lockedVenue())
		#expect(card.venueName == "Blue Tokai")
		#expect(card.pulseMessage?.localizedCaseInsensitiveContains("Blue Tokai") == true)
	}

	private func sampleCandidates() -> GroundedVenueCandidates {
		PulseComposePreviewData.candidates
	}
}
