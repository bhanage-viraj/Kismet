import CoreLocation
import Foundation
import Testing
import UIKit
@testable import Kismet

struct SuggestionSnapshotWriterTests {
	@Test func mapsFreeFriendAndFeaturedMeetup() {
		let card = SuggestionCard(
			id: "f1",
			friendID: "f1",
			displayName: "Aarav Shah",
			coordinate: CLLocationCoordinate2D(latitude: 12.97, longitude: 77.59),
			availability: .free,
			presence: .available,
			distanceMeters: 350,
			reason: "Free nearby · Good time for coffee",
			reasonCodes: [],
			factChips: ["Free until 4:30 PM", "5 min walk"],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: "Third Wave",
			venueETAMinutes: 5,
			confidence: 0.8,
			urgency: .now,
			isModelGenerated: false
		)

		let snapshot = SuggestionSnapshotWriter.makeSnapshot(from: [card])

		#expect(snapshot.friendCountNearby == 1)
		#expect(snapshot.headline == "1 friend free nearby")
		#expect(snapshot.cards.first?.initials == "AS")
		#expect(snapshot.cards.first?.status == .free)
		#expect(snapshot.cards.first?.freeUntilText == "Free until 4:30 PM")
		#expect(snapshot.cards.first?.statusLabel == "Free until 4:30 PM")
		#expect(snapshot.cards.first?.distanceText == "350 m away")
		#expect(snapshot.cards.first?.avatarFileName == nil)
		#expect(snapshot.cards.first?.latitude == 12.97)
		#expect(snapshot.cards.first?.longitude == 77.59)
		#expect(snapshot.featuredMeetup?.venueName == "Third Wave")
		#expect(snapshot.featuredMeetup?.etaText == "5 min")
	}

	@Test func approximateUsesNearbyDistance() {
		let card = SuggestionCard(
			id: "f2",
			friendID: "f2",
			displayName: "Neha",
			coordinate: CLLocationCoordinate2D(latitude: 12.97, longitude: 77.59),
			availability: .unknown,
			presence: .approximate,
			distanceMeters: 1200,
			reason: "Nearby",
			reasonCodes: [],
			factChips: [],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: nil,
			venueETAMinutes: nil,
			confidence: 0.5,
			urgency: .soon,
			isModelGenerated: false
		)

		let snapshot = SuggestionSnapshotWriter.makeSnapshot(from: [card])
		#expect(snapshot.cards.first?.status == .nearby)
		#expect(snapshot.cards.first?.distanceText == "Nearby")
		#expect(snapshot.headline == "1 friend nearby")
		#expect(snapshot.cards.first?.avatarFileName == nil)
	}

	@Test func encodeDecodeRoundTripPreservesOptionalAvatarFileName() throws {
		let snapshot = SuggestionSnapshotWriter.makeSnapshot(from: [])
		let data = try JSONEncoder().encode(snapshot)
		let decoded = try JSONDecoder().decode(AppGroup.SuggestionSnapshot.self, from: data)
		#expect(decoded == snapshot)
		#expect(decoded.cards.allSatisfy { $0.avatarFileName == nil })
	}

	@Test func persistsAvatarImageWhenProvided() throws {
		let imageData = try #require(tinyJPEGData())
		let card = SuggestionCard(
			id: "f-photo",
			friendID: "friend-photo-1",
			displayName: "Aarav",
			coordinate: CLLocationCoordinate2D(latitude: 12.97, longitude: 77.59),
			availability: .free,
			presence: .available,
			distanceMeters: 350,
			reason: "Free nearby",
			reasonCodes: [],
			factChips: ["Free until 4:30 PM"],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: nil,
			venueETAMinutes: nil,
			confidence: 0.8,
			urgency: .now,
			isModelGenerated: false,
			avatarImageData: imageData
		)

		let snapshot = SuggestionSnapshotWriter.makeSnapshot(from: [card])

		guard AppGroup.containerURL != nil else {
			#expect(snapshot.cards.first?.avatarFileName == nil)
			return
		}

		let fileName = try #require(snapshot.cards.first?.avatarFileName)
		#expect(fileName.hasSuffix(".jpg"))
		#expect(AppGroup.loadAvatarImage(fileName: fileName) != nil)

		// Empty snapshot prunes leftover avatar files.
		_ = SuggestionSnapshotWriter.makeSnapshot(from: [])
		#expect(AppGroup.loadAvatarImage(fileName: fileName) == nil)
	}

	@Test func decodesLegacySnapshotWithoutAvatarFileName() throws {
		struct LegacyCard: Encodable {
			var id: String
			var friendID: String
			var displayName: String
			var initials: String
			var status: String
			var statusLabel: String
			var distanceText: String
			var reason: String
			var ctaTitle: String
		}

		struct LegacySnapshot: Encodable {
			var schemaVersion: Int
			var updatedAt: Date
			var headline: String
			var friendCountNearby: Int
			var cards: [LegacyCard]
		}

		let legacy = LegacySnapshot(
			schemaVersion: 1,
			updatedAt: .now,
			headline: "1 friend nearby",
			friendCountNearby: 1,
			cards: [
				LegacyCard(
					id: "legacy",
					friendID: "legacy",
					displayName: "Aarav",
					initials: "A",
					status: "free",
					statusLabel: "Free until 4:30 PM",
					distanceText: "350 m away",
					reason: "Free nearby",
					ctaTitle: "Send a Pulse"
				)
			]
		)

		let data = try JSONEncoder().encode(legacy)
		let decoded = try JSONDecoder().decode(AppGroup.SuggestionSnapshot.self, from: data)
		#expect(decoded.cards.first?.avatarFileName == nil)
		#expect(decoded.cards.first?.displayName == "Aarav")
	}

	private func tinyJPEGData() -> Data? {
		UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).jpegData(withCompressionQuality: 0.8) { context in
			UIColor.systemGreen.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
		}
	}
}
