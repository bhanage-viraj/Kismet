import AppIntents
import CoreSpotlight
import Foundation

struct FriendEntity: AppEntity, IndexedEntity {
	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Friend")
	static var defaultQuery = FriendEntityQuery()

	var id: String
	var displayName: String
	var presenceRaw: String
	var distanceText: String
	var statusSummary: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(displayName)",
			subtitle: "\(statusSummary)"
		)
	}

	/// Eclipse-hidden friends must never be donated to Siri/Spotlight.
	var isSiriVisible: Bool {
		PresenceState(rawValue: presenceRaw)?.isSuggestionEligible ?? false
	}

	var attributeSet: CSSearchableItemAttributeSet {
		let attrs = defaultAttributeSet
		attrs.displayName = displayName
		attrs.title = displayName
		attrs.contentDescription = statusSummary
		attrs.keywords = ["friend", "kismet", "availability", presenceRaw, displayName]
		return attrs
	}

	static func from(card: SuggestionCard) -> FriendEntity? {
		guard card.presence.isSuggestionEligible else { return nil }
		var summary = "\(card.displayName) is \(card.presence.spokenLabel)"
		if card.presence.showsPreciseLocation {
			summary += ", \(card.formattedDistance)"
		} else {
			summary += ", nearby"
		}
		if let venue = card.venueName, !venue.isEmpty {
			summary += ", near \(venue)"
		}
		return FriendEntity(
			id: card.friendID,
			displayName: card.displayName,
			presenceRaw: card.presence.rawValue,
			distanceText: card.formattedDistance,
			statusSummary: summary
		)
	}

	static func from(person: MapPerson) -> FriendEntity? {
		guard person.presenceState.isSuggestionEligible else { return nil }
		var summary = "\(person.displayName) is \(person.presenceState.spokenLabel)"
		if person.presenceState.showsPreciseLocation {
			summary += ", \(person.formattedDistance)"
		} else {
			summary += ", nearby"
		}
		if !person.insightSummary.isEmpty {
			let firstLine = person.insightSummary
				.split(separator: "\n", omittingEmptySubsequences: true)
				.first
				.map(String.init)
			if let firstLine, !firstLine.isEmpty {
				summary = "\(person.displayName): \(firstLine)"
			}
		}
		return FriendEntity(
			id: person.id,
			displayName: person.displayName,
			presenceRaw: person.presenceState.rawValue,
			distanceText: person.formattedDistance,
			statusSummary: summary
		)
	}
}

struct FriendEntityQuery: EntityStringQuery {
	func entities(for identifiers: [FriendEntity.ID]) async throws -> [FriendEntity] {
		let all = await Self.siriVisibleFriends()
		return all.filter { identifiers.contains($0.id) }
	}

	func suggestedEntities() async throws -> [FriendEntity] {
		await Self.siriVisibleFriends()
	}

	func entities(matching string: String) async throws -> [FriendEntity] {
		let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !needle.isEmpty else { return try await suggestedEntities() }
		return await Self.siriVisibleFriends().filter {
			$0.displayName.localizedCaseInsensitiveContains(needle)
				|| $0.statusSummary.localizedCaseInsensitiveContains(needle)
		}
	}

	@MainActor
	static func siriVisibleFriends() -> [FriendEntity] {
		var byID: [String: FriendEntity] = [:]

		for person in AppEnvironment.shared.mapFriendsStore.friends {
			if let entity = FriendEntity.from(person: person) {
				byID[entity.id] = entity
			}
		}

		for card in AppEnvironment.shared.suggestionEngine.store.cards {
			guard byID[card.friendID] == nil, let entity = FriendEntity.from(card: card) else { continue }
			byID[entity.id] = entity
		}

		// Seeded friends may be in the friend list before map refresh finishes.
		for friend in AppEnvironment.shared.friendsStore.friends {
			guard byID[friend.userId] == nil else { continue }
			let name = friend.displayName ?? "Friend"
			guard name.hasSuffix(" (Test)") else { continue }
			byID[friend.userId] = FriendEntity(
				id: friend.userId,
				displayName: name,
				presenceRaw: PresenceState.available.rawValue,
				distanceText: "Nearby",
				statusSummary: "\(name) is available nearby"
			)
		}

		return Array(byID.values).sorted {
			$0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
		}
	}
}
