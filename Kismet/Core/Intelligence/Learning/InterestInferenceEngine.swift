import Foundation
import Observation

/// Deterministic soft interest suggestions from meetup categories (never auto-saves).
struct InterestInferenceEngine: Sendable {
	/// Minimum completed meetups in a category before suggesting the mapped interest.
	var minimumCompletions: Int = 2

	func suggest(
		meetups: [MeetupEventSnapshot],
		currentInterests: [String],
		dismissedInterestIDs: Set<String>
	) -> [String] {
		let owned = Set(currentInterests.map { $0.lowercased() })
		var counts: [String: Int] = [:]

		for meetup in meetups where meetup.outcome == .completed {
			guard let interestID = InterestCatalog.interestID(for: meetup.venueCategory) else { continue }
			counts[interestID, default: 0] += 1
		}

		return counts
			.filter { $0.value >= minimumCompletions }
			.filter { !owned.contains($0.key.lowercased()) }
			.filter { !dismissedInterestIDs.contains($0.key) }
			.sorted { lhs, rhs in
				if lhs.value != rhs.value { return lhs.value > rhs.value }
				return lhs.key < rhs.key
			}
			.map(\.key)
	}
}

@Observable
@MainActor
final class InterestSuggestionStore {
	private(set) var pending: [String] = []

	private let defaults: UserDefaults
	private let dismissedKey = "kismet.interestSuggestions.dismissed"
	private let engine: InterestInferenceEngine

	init(
		defaults: UserDefaults = .standard,
		engine: InterestInferenceEngine = InterestInferenceEngine()
	) {
		self.defaults = defaults
		self.engine = engine
	}

	func refresh(meetups: [MeetupEventSnapshot], currentInterests: [String]) {
		pending = engine.suggest(
			meetups: meetups,
			currentInterests: currentInterests,
			dismissedInterestIDs: dismissedIDs
		)
	}

	func dismiss(_ interestID: String) {
		var set = dismissedIDs
		set.insert(interestID)
		defaults.set(Array(set), forKey: dismissedKey)
		pending.removeAll { $0 == interestID }
	}

	func removeAccepted(_ interestID: String) {
		pending.removeAll { $0 == interestID }
	}

	#if DEBUG
	func previewSetPending(_ ids: [String]) {
		pending = ids
	}
	#endif

	private var dismissedIDs: Set<String> {
		Set(defaults.stringArray(forKey: dismissedKey) ?? [])
	}
}
