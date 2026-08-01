import Foundation

enum WidgetAppGroup {
	static let suiteName = "group.sanjivanand.kismet"
	static let suggestionSnapshotKey = "suggestionSnapshot"

	struct SuggestionSnapshot: Codable {
		var updatedAt: Date
		var cards: [Card]
	}

	struct Card: Codable, Identifiable {
		var id: String
		var friendID: String
		var displayName: String
		var reason: String
		var ctaTitle: String
		var venueName: String?
		var freeUntilText: String?
		var distanceText: String
	}

	static func loadSnapshot() -> SuggestionSnapshot? {
		guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: suggestionSnapshotKey) else {
			return nil
		}
		return try? JSONDecoder().decode(SuggestionSnapshot.self, from: data)
	}
}
