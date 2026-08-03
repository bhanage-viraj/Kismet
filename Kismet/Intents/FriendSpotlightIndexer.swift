import AppIntents
import CoreSpotlight
import Foundation

/// Donates Siri-visible friends into Spotlight’s semantic index so Apple Intelligence
/// can answer questions about friend status from Kismet content.
enum FriendSpotlightIndexer {
	private static let indexName = "kismet.friends"

	@MainActor
	static func reindex() async {
		guard CSSearchableIndex.isIndexingAvailable() else { return }

		let entities = FriendEntityQuery.siriVisibleFriends()
		let index = CSSearchableIndex(name: indexName)

		do {
			try await index.deleteAppEntities(ofType: FriendEntity.self)
			if !entities.isEmpty {
				try await index.indexAppEntities(entities)
			}
		} catch {
			// Best-effort — Siri App Shortcuts still work without the semantic index.
		}
	}
}
