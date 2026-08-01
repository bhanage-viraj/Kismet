import AppIntents
import Foundation

struct FriendEntity: AppEntity, Identifiable {
	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Friend")
	static var defaultQuery = FriendEntityQuery()

	var id: String
	var displayName: String
	var presenceRaw: String
	var distanceText: String

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "\(displayName)",
			subtitle: "\(distanceText)"
		)
	}

	/// Eclipse-hidden friends must never be donated to Siri/Spotlight.
	var isSiriVisible: Bool {
		PresenceState(rawValue: presenceRaw)?.isSuggestionEligible ?? false
	}
}

struct FriendEntityQuery: EntityQuery {
	func entities(for identifiers: [FriendEntity.ID]) async throws -> [FriendEntity] {
		let cards = await MainActor.run {
			AppEnvironment.shared.suggestionEngine.store.cards
		}
		return cards
			.filter { identifiers.contains($0.friendID) && $0.presence.isSuggestionEligible }
			.map {
				FriendEntity(
					id: $0.friendID,
					displayName: $0.displayName,
					presenceRaw: $0.presence.rawValue,
					distanceText: $0.formattedDistance
				)
			}
	}

	func suggestedEntities() async throws -> [FriendEntity] {
		let cards = await MainActor.run {
			AppEnvironment.shared.suggestionEngine.store.cards
		}
		return cards
			.filter(\.presence.isSuggestionEligible)
			.map {
				FriendEntity(
					id: $0.friendID,
					displayName: $0.displayName,
					presenceRaw: $0.presence.rawValue,
					distanceText: $0.formattedDistance
				)
			}
	}
}
