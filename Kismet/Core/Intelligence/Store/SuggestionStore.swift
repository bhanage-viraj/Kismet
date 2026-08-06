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

	/// Load last App Group snapshot into memory when Siri/intents run with a cold store.
	@discardableResult
	func rehydrateFromAppGroupIfNeeded() -> Bool {
		guard cards.isEmpty else { return false }
		guard let snapshot = AppGroup.loadSnapshot(),
		      !snapshot.isStale,
		      !snapshot.cards.isEmpty
		else { return false }

		let restored = snapshot.cards
			.map(SuggestionCard.fromAppGroup)
			.filter(\.presence.isSuggestionEligible)
		guard !restored.isEmpty else { return false }

		cards = restored
		lastUpdatedAt = snapshot.updatedAt
		statusMessage = nil
		usedFoundationModels = false
		return true
	}

	func reset() {
		cards = []
		lastUpdatedAt = nil
		statusMessage = nil
		usedFoundationModels = false
		SuggestionSnapshotWriter.clear()
	}
}
