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
		self.statusMessage = status
		self.lastUpdatedAt = Date()
		SuggestionSnapshotWriter.persist(
			cards: self.cards,
			updatedAt: self.lastUpdatedAt ?? Date(),
			userCoordinate: userCoordinate
		)
	}

	func reset() {
		cards = []
		lastUpdatedAt = nil
		statusMessage = nil
		usedFoundationModels = false
		SuggestionSnapshotWriter.clear()
	}
}
