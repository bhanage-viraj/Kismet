import CoreLocation
import Foundation

struct FriendPresenceProvider: ContextProviding {
	private let people: [MapPerson]

	init(people: [MapPerson]) {
		self.people = people
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
				freeUntil: person.freeUntil,
				freeFrom: person.freeFrom,
				lastSeenAt: nil,
				locationAccuracy: nil
			)
		}
	}
}
