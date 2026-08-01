import CoreLocation
import Foundation

struct FriendPresenceProvider: ContextProviding {
	private let people: [MapPerson]
	private let freeUntilByID: [String: Date]
	private let freeFromByID: [String: Date]

	init(
		people: [MapPerson],
		freeUntilByID: [String: Date] = [:],
		freeFromByID: [String: Date] = [:]
	) {
		self.people = people
		self.freeUntilByID = freeUntilByID
		self.freeFromByID = freeFromByID
	}

	func current() async -> [FriendPresence] {
		people.compactMap { person in
			let presence = person.presenceState
			guard presence.isSurfaceVisible else { return nil }
			return FriendPresence(
				id: person.id,
				displayName: person.displayName,
				coordinate: person.coordinate,
				presence: presence,
				distanceMeters: person.distanceMeters,
				sharedInterests: person.sharedInterests,
				freeUntil: freeUntilByID[person.id],
				freeFrom: freeFromByID[person.id],
				lastSeenAt: nil,
				locationAccuracy: nil
			)
		}
	}
}
