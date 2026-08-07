import Foundation
import Observation
import CoreLocation

@Observable
@MainActor
final class SuggestionStore {
	private(set) var cards: [SuggestionCard] = []
	private(set) var isRefreshing = false
	private(set) var lastUpdatedAt: Date?
	private(set) var statusMessage: String?
	private(set) var usedFoundationModels = false

	func setRefreshing(_ value: Bool) {
		isRefreshing = value
	}

	func replace(
		cards: [SuggestionCard],
		usedModel: Bool,
		status: String? = nil,
		userCoordinate: CLLocationCoordinate2D? = nil
	) {
		self.cards = cards.filter { $0.presence.isSuggestionEligible }
		self.usedFoundationModels = usedModel
		self.statusMessage = Self.sanitizedStatus(status)
		self.lastUpdatedAt = Date()
		SuggestionSnapshotWriter.persist(
			cards: self.cards,
			updatedAt: self.lastUpdatedAt ?? Date(),
			userCoordinate: userCoordinate
		)
		Task { await FriendSpotlightIndexer.reindex() }
	}

	private static func sanitizedStatus(_ status: String?) -> String? {
		guard let status else { return nil }
		let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		let lower = trimmed.lowercased()
		if lower.contains("cancellationerror")
			|| lower.contains("couldn't be completed")
			|| lower.contains("could not be completed") {
			return nil
		}
		return trimmed
	}

	func reset() {
		cards = []
		lastUpdatedAt = nil
		statusMessage = nil
		usedFoundationModels = false
		SuggestionSnapshotWriter.clear()
		Task { await FriendSpotlightIndexer.reindex() }
	}
}
