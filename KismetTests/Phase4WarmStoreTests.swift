import CoreLocation
import Foundation
import Testing
@testable import Kismet

struct Phase4WarmStoreTests {
	private let origin = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	@Test func friendPresenceProviderReadsFreeWindowsFromMapPerson() async {
		let until = Date().addingTimeInterval(3600)
		let from = Date().addingTimeInterval(7200)
		let person = MapPerson(
			id: "ada",
			displayName: "Ada",
			coordinate: origin,
			availability: .free,
			presenceState: .available,
			distanceMeters: 200,
			sharedInterests: ["coffee"],
			freeUntil: until,
			freeFrom: from,
			insightSummary: "Free",
			intentLabel: "Free",
			neighborhoodLabel: "Nearby",
			mutualFriendCount: 0,
			accentSystemImage: "person.fill",
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right"
		)

		let friends = await FriendPresenceProvider(people: [person]).current()
		#expect(friends.count == 1)
		#expect(friends.first?.freeUntil == until)
		#expect(friends.first?.freeFrom == from)
	}

	@Test func freeUntilMapsIntoFactChips() {
		let until = Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: Date())!
		let friend = FriendPresence(
			id: "ada",
			displayName: "Ada",
			coordinate: origin,
			presence: .available,
			distanceMeters: 200,
			sharedInterests: ["coffee"],
			freeUntil: until,
			freeFrom: nil,
			lastSeenAt: nil,
			locationAccuracy: nil
		)
		let item = RankedOpportunity(
			friend: friend,
			score: 3,
			reasonCodes: [.bothFree, .nearbyWalk],
			learnedStats: nil
		)
		let chips = FallbackComposer.factChips(for: item)
		#expect(chips.contains(where: { $0.localizedCaseInsensitiveContains("Free until") }))
	}

	@Test func suggestionCardRoundTripsThroughAppGroupWarmFields() throws {
		let card = SuggestionCard(
			id: "ada",
			friendID: "ada",
			displayName: "Ada",
			coordinate: origin,
			availability: .free,
			presence: .available,
			distanceMeters: 220,
			reason: "Both free",
			reasonCodes: [.bothFree],
			factChips: ["Free until 4:30 PM", "3 min walk"],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: "Third Wave",
			venueETAMinutes: 3,
			confidence: 0.9,
			urgency: .now,
			isModelGenerated: true,
			pulseMessage: "Free to grab coffee?"
		)

		let snapshot = SuggestionSnapshotWriter.makeSnapshot(from: [card])
		let widget = try #require(snapshot.cards.first)
		#expect(widget.presenceRaw == PresenceState.available.rawValue)
		#expect(widget.distanceMeters == 220)
		#expect(widget.pulseMessage == "Free to grab coffee?")

		let restored = SuggestionCard.fromAppGroup(widget)
		#expect(restored.friendID == "ada")
		#expect(restored.presence == .available)
		#expect(restored.distanceMeters == 220)
		#expect(restored.pulseMessage == "Free to grab coffee?")
		#expect(restored.venueName == "Third Wave")
		#expect(restored.factChips.contains(where: { $0.contains("Free until") }))
	}

	@Test func confirmReconstructsFromDraftWhenStoreEmpty() {
		let draft = PulseDraft(
			friendID: "ada",
			displayName: "Ada",
			venueName: "Blue Tokai",
			message: "Free to grab coffee?",
			suggestionCardID: "ada"
		)
		let card = SuggestionCard.fromPulseDraft(draft)
		#expect(card.friendID == "ada")
		#expect(card.presence.isSuggestionEligible)
		#expect(card.pulseMessage == "Free to grab coffee?")
		#expect(card.venueName == "Blue Tokai")
	}

	@Test func confirmPrefersSnapshotCardWhenReconstructing() {
		let draft = PulseDraft(
			friendID: "ada",
			displayName: "Ada",
			venueName: nil,
			message: "Free to hang soon?",
			suggestionCardID: "ada"
		)
		let snapshotCard = AppGroup.Card(
			id: "ada",
			friendID: "ada",
			displayName: "Ada",
			initials: "A",
			status: .free,
			statusLabel: "Free until 4:30 PM",
			distanceText: "220 m away",
			reason: "Both free",
			ctaTitle: "Send a Pulse",
			venueName: "Third Wave",
			freeUntilText: "Free until 4:30 PM",
			latitude: origin.latitude,
			longitude: origin.longitude,
			presenceRaw: PresenceState.available.rawValue,
			distanceMeters: 220
		)
		let card = SuggestionCard.fromPulseDraft(draft, snapshotCard: snapshotCard)
		#expect(card.venueName == "Third Wave")
		#expect(card.pulseMessage == "Free to hang soon?")
		#expect(card.distanceMeters == 220)
	}

	@Test @MainActor func rehydrateLoadsSnapshotIntoEmptyStore() {
		let store = SuggestionStore()
		#expect(store.cards.isEmpty)

		let card = SuggestionCard(
			id: "friend-warm-1",
			friendID: "friend-warm-1",
			displayName: "Ada",
			coordinate: origin,
			availability: .free,
			presence: .available,
			distanceMeters: 180,
			reason: "Free nearby",
			reasonCodes: [.bothFree],
			factChips: ["Free until 4:30 PM"],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: nil,
			venueETAMinutes: nil,
			confidence: 0.7,
			urgency: .now,
			isModelGenerated: false,
			pulseMessage: "Free to hang soon?"
		)
		SuggestionSnapshotWriter.persist(cards: [card], userCoordinate: origin)

		guard AppGroup.loadSnapshot() != nil else {
			// App Group suite unavailable in this test host — skip silently.
			return
		}

		let didRehydrate = store.rehydrateFromAppGroupIfNeeded()
		#expect(didRehydrate)
		#expect(store.cards.first?.friendID == "friend-warm-1")
		#expect(store.cards.first?.pulseMessage == "Free to hang soon?")
	}
}
