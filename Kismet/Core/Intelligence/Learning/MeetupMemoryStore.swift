import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class MeetupMemoryStore {
	private(set) var recentMeetups: [MeetupEvent] = []
	private(set) var recentFeedback: [SuggestionFeedback] = []
	private(set) var learnedProfile: LearnedProfileSnapshot?
	private(set) var lastErrorMessage: String?

	private let modelContext: ModelContext

	init(modelContext: ModelContext) {
		self.modelContext = modelContext
		refreshCaches()
	}

	convenience init(container: ModelContainer) {
		self.init(modelContext: ModelContext(container))
	}

	/// Call once after environment is ready so Spotlight can recover items.
	func attachSpotlightIndexer() {
		MeetupSpotlightIndexer.shared.attach(memoryStore: self)
		MeetupSpotlightIndexer.shared.reindexAll(from: self)
	}

	// MARK: - Meetup events

	@discardableResult
	func recordMeetup(
		friendUserId: String,
		friendDisplayName: String,
		venueName: String? = nil,
		source: MeetupSource,
		outcome: MeetupOutcome = .pending,
		startedAt: Date = Date()
	) -> MeetupEvent {
		let event = MeetupEvent(
			friendUserId: friendUserId,
			friendDisplayName: friendDisplayName,
			startedAt: startedAt,
			venueName: venueName,
			venueCategory: VenueCategory.infer(from: venueName),
			source: source,
			outcome: outcome
		)
		modelContext.insert(event)
		save()
		refreshCaches()
		indexMeetup(event)
		return event
	}

	func markCompleted(eventID: UUID, endedAt: Date = Date()) {
		guard let event = fetchMeetup(id: eventID) else { return }
		event.outcome = .completed
		event.endedAt = endedAt
		save()
		refreshCaches()
		indexMeetup(event)
	}

	func markCompleted(
		friendUserId: String,
		friendDisplayName: String,
		venueName: String? = nil
	) {
		if let pending = recentMeetups.first(where: {
			$0.friendUserId == friendUserId && $0.outcome == .pending
		}) {
			markCompleted(eventID: pending.id)
			return
		}
		_ = recordMeetup(
			friendUserId: friendUserId,
			friendDisplayName: friendDisplayName,
			venueName: venueName,
			source: .manual,
			outcome: .completed,
			startedAt: Date()
		)
	}

	func updateOutcome(eventID: UUID, outcome: MeetupOutcome) {
		guard let event = fetchMeetup(id: eventID) else { return }
		event.outcome = outcome
		if outcome == .completed, event.endedAt == nil {
			event.endedAt = Date()
		}
		save()
		refreshCaches()
		indexMeetup(event)
	}

	func meetups(for friendUserId: String) -> [MeetupEvent] {
		recentMeetups.filter { $0.friendUserId == friendUserId }
	}

	func completedMeetups(limit: Int = 50) -> [MeetupEvent] {
		Array(
			recentMeetups
				.filter { $0.outcome == .completed }
				.prefix(limit)
		)
	}

	// MARK: - Suggestion feedback

	@discardableResult
	func recordFeedback(
		friendUserId: String,
		action: SuggestionFeedbackAction,
		reasonCodes: [String] = []
	) -> SuggestionFeedback {
		let feedback = SuggestionFeedback(
			friendUserId: friendUserId,
			action: action,
			reasonCodes: reasonCodes
		)
		modelContext.insert(feedback)
		save()
		refreshCaches()
		return feedback
	}

	func feedback(for friendUserId: String) -> [SuggestionFeedback] {
		recentFeedback.filter { $0.friendUserId == friendUserId }
	}

	/// Sendable snapshots for ranking / feature extraction off the model objects.
	func meetupSnapshots() -> [MeetupEventSnapshot] {
		recentMeetups.map {
			MeetupEventSnapshot(
				id: $0.id,
				friendUserId: $0.friendUserId,
				friendDisplayName: $0.friendDisplayName,
				startedAt: $0.startedAt,
				endedAt: $0.endedAt,
				venueName: $0.venueName,
				venueCategory: $0.venueCategory,
				source: $0.source,
				outcome: $0.outcome
			)
		}
	}

	func feedbackSnapshots() -> [SuggestionFeedbackSnapshot] {
		recentFeedback.map {
			SuggestionFeedbackSnapshot(
				id: $0.id,
				friendUserId: $0.friendUserId,
				createdAt: $0.createdAt,
				action: $0.action,
				reasonCodes: $0.reasonCodes
			)
		}
	}

	func buildLearnedSlice(builder: LearnedFeatureBuilder = LearnedFeatureBuilder()) -> LearnedSlice {
		let slice = builder.build(
			meetups: meetupSnapshots(),
			feedback: feedbackSnapshots(),
			existingSummary: learnedProfile?.summaryText
		)
		if slice.hasSignal {
			upsertLearnedProfile(
				summaryText: slice.summaryText,
				topFriendIds: slice.topFriendIds,
				preferredHours: slice.preferredHours,
				preferredCategories: slice.preferredCategories.map(\.rawValue)
			)
		}
		return slice
	}

	private func indexMeetup(_ event: MeetupEvent) {
		MeetupSpotlightIndexer.shared.upsertMeetup(
			MeetupEventSnapshot(
				id: event.id,
				friendUserId: event.friendUserId,
				friendDisplayName: event.friendDisplayName,
				startedAt: event.startedAt,
				endedAt: event.endedAt,
				venueName: event.venueName,
				venueCategory: event.venueCategory,
				source: event.source,
				outcome: event.outcome
			)
		)
	}

	// MARK: - Learned profile snapshot

	func upsertLearnedProfile(
		summaryText: String,
		topFriendIds: [String],
		preferredHours: [Int],
		preferredCategories: [String]
	) {
		if let existing = fetchLatestProfile() {
			existing.updatedAt = Date()
			existing.summaryText = summaryText
			existing.topFriendIds = topFriendIds
			existing.preferredHours = preferredHours
			existing.preferredCategories = preferredCategories
		} else {
			let snapshot = LearnedProfileSnapshot(
				summaryText: summaryText,
				topFriendIds: topFriendIds,
				preferredHours: preferredHours,
				preferredCategories: preferredCategories
			)
			modelContext.insert(snapshot)
		}
		save()
		refreshCaches()
		MeetupSpotlightIndexer.shared.upsertHabits(from: self)
	}

	// MARK: - Private

	private func fetchMeetup(id: UUID) -> MeetupEvent? {
		let descriptor = FetchDescriptor<MeetupEvent>(
			predicate: #Predicate { $0.id == id }
		)
		return try? modelContext.fetch(descriptor).first
	}

	private func fetchLatestProfile() -> LearnedProfileSnapshot? {
		var descriptor = FetchDescriptor<LearnedProfileSnapshot>(
			sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try? modelContext.fetch(descriptor).first
	}

	private func refreshCaches() {
		do {
			var meetupDescriptor = FetchDescriptor<MeetupEvent>(
				sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
			)
			meetupDescriptor.fetchLimit = 100
			recentMeetups = try modelContext.fetch(meetupDescriptor)

			var feedbackDescriptor = FetchDescriptor<SuggestionFeedback>(
				sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
			)
			feedbackDescriptor.fetchLimit = 200
			recentFeedback = try modelContext.fetch(feedbackDescriptor)

			learnedProfile = fetchLatestProfile()
			lastErrorMessage = nil
		} catch {
			lastErrorMessage = error.localizedDescription
		}
	}

	private func save() {
		do {
			try modelContext.save()
			lastErrorMessage = nil
		} catch {
			lastErrorMessage = error.localizedDescription
		}
	}
}
