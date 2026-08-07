import Foundation

/// Sealed inside MEETUP blobs — notifies the Pulse sender that a meetup was accepted
/// so both devices can start the same Live Activity.
struct MeetupPayloadDTO: Codable, Sendable, Equatable {
	var meetupId: String
	var title: String
	var venueName: String?
	var meetAt: Date?
	var peerDisplayName: String
	var systemImage: String
	var createdAt: Date
}
