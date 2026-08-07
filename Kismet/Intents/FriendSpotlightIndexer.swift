import AppIntents
import CoreSpotlight
import Foundation

/// Donates Siri-visible friends into Spotlight’s semantic index so Apple Intelligence
/// can answer questions about friend status from Who's Out content.
enum FriendSpotlightIndexer {
	private static let indexName = "whosout.friends"
	private static let minInterval: TimeInterval = 60
	@MainActor private static var lastIndexedAt: Date?

	@MainActor
	static func reindex(force: Bool = false) async {
		guard CSSearchableIndex.isIndexingAvailable() else { return }
		if !force, let lastIndexedAt, Date().timeIntervalSince(lastIndexedAt) < minInterval {
			return
		}

		let entities = FriendEntityQuery.siriVisibleFriends()
		let index = CSSearchableIndex(name: indexName)

		do {
			try await index.deleteAppEntities(ofType: FriendEntity.self)
			if !entities.isEmpty {
				try await index.indexAppEntities(entities)
			}
			lastIndexedAt = Date()
		} catch {
			// Best-effort — Siri App Shortcuts still work without the semantic index.
		}
	}
}
