import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Donates meetup history into Core Spotlight for on-device RAG via SpotlightSearchTool (iOS 27+).
/// Does not index live presence or coordinates.
@MainActor
final class MeetupSpotlightIndexer: NSObject {
	static let shared = MeetupSpotlightIndexer()

	static let domainIdentifier = "com.kismet.meetup-memory"
	static let habitsItemIdentifier = "kismet.learned-habits"

	private let index: CSSearchableIndex
	private weak var memoryStore: MeetupMemoryStore?

	private override init() {
		self.index = .default()
		super.init()
		index.indexDelegate = self
	}

	func attach(memoryStore: MeetupMemoryStore) {
		self.memoryStore = memoryStore
	}

	func reindexAll(from store: MeetupMemoryStore) {
		attach(memoryStore: store)
		let meetups = store.meetupSnapshots().filter {
			$0.outcome == .completed || $0.outcome == .pending
		}
		var items = meetups.map(makeMeetupItem)
		if let habits = makeHabitsItem(from: store) {
			items.append(habits)
		}
		guard !items.isEmpty else {
			index.deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier]) { _ in }
			return
		}
		index.indexSearchableItems(items) { error in
			if let error {
				#if DEBUG
				print("MeetupSpotlightIndexer reindex error: \(error.localizedDescription)")
				#endif
			}
		}
	}

	func upsertMeetup(_ snapshot: MeetupEventSnapshot) {
		guard snapshot.outcome == .completed || snapshot.outcome == .pending else {
			deleteMeetup(id: snapshot.id)
			return
		}
		index.indexSearchableItems([makeMeetupItem(from: snapshot)]) { _ in }
	}

	func upsertHabits(from store: MeetupMemoryStore) {
		guard let item = makeHabitsItem(from: store) else { return }
		index.indexSearchableItems([item]) { _ in }
	}

	func deleteMeetup(id: UUID) {
		index.deleteSearchableItems(withIdentifiers: [meetupIdentifier(id)]) { _ in }
	}

	// MARK: - Item builders

	private func meetupIdentifier(_ id: UUID) -> String {
		"kismet.meetup.\(id.uuidString)"
	}

	private func makeMeetupItem(from snapshot: MeetupEventSnapshot) -> CSSearchableItem {
		let attributes = CSSearchableItemAttributeSet(contentType: .content)
		let venueBit = snapshot.venueName.map { " at \($0)" } ?? ""
		let title = "Meetup with \(snapshot.friendDisplayName)\(venueBit)"
		attributes.title = title
		attributes.displayName = title
		attributes.contentDescription = [
			"Friend: \(snapshot.friendDisplayName)",
			"Category: \(snapshot.venueCategory.rawValue)",
			"Outcome: \(snapshot.outcome.rawValue)",
			snapshot.venueName.map { "Venue: \($0)" }
		]
		.compactMap { $0 }
		.joined(separator: ". ")
		attributes.keywords = [
			"meetup",
			"hangout",
			snapshot.friendDisplayName,
			snapshot.venueCategory.rawValue,
			snapshot.venueName
		].compactMap { $0 }
		attributes.startDate = snapshot.startedAt
		attributes.endDate = snapshot.endedAt
		attributes.contentCreationDate = snapshot.startedAt

		let item = CSSearchableItem(
			uniqueIdentifier: meetupIdentifier(snapshot.id),
			domainIdentifier: Self.domainIdentifier,
			attributeSet: attributes
		)
		item.expirationDate = .distantFuture
		return item
	}

	private func makeHabitsItem(from store: MeetupMemoryStore) -> CSSearchableItem? {
		guard let profile = store.learnedProfile, !profile.summaryText.isEmpty else { return nil }
		let attributes = CSSearchableItemAttributeSet(contentType: .content)
		attributes.title = "Kismet hangout habits"
		attributes.displayName = "Kismet hangout habits"
		let hours = profile.preferredHours.map { String(format: "%02d:00", $0) }.joined(separator: ", ")
		let cats = profile.preferredCategories.joined(separator: ", ")
		attributes.contentDescription = [
			profile.summaryText,
			hours.isEmpty ? nil : "Usual hours: \(hours)",
			cats.isEmpty ? nil : "Preferred categories: \(cats)"
		]
		.compactMap { $0 }
		.joined(separator: ". ")
		attributes.keywords = ["habits", "meetup", "usual"] + profile.preferredCategories
		attributes.contentModificationDate = profile.updatedAt

		let item = CSSearchableItem(
			uniqueIdentifier: Self.habitsItemIdentifier,
			domainIdentifier: Self.domainIdentifier,
			attributeSet: attributes
		)
		item.expirationDate = .distantFuture
		return item
	}
}

extension MeetupSpotlightIndexer: CSSearchableIndexDelegate {
	nonisolated func searchableIndex(
		_ searchableIndex: CSSearchableIndex,
		reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void
	) {
		Task { @MainActor in
			if let store = memoryStore {
				reindexAll(from: store)
			}
			acknowledgementHandler()
		}
	}

	nonisolated func searchableIndex(
		_ searchableIndex: CSSearchableIndex,
		reindexSearchableItemsWithIdentifiers identifiers: [String],
		acknowledgementHandler: @escaping () -> Void
	) {
		Task { @MainActor in
			guard let store = memoryStore else {
				acknowledgementHandler()
				return
			}
			var items: [CSSearchableItem] = []
			for id in identifiers {
				if id == Self.habitsItemIdentifier {
					if let habits = makeHabitsItem(from: store) {
						items.append(habits)
					}
					continue
				}
				guard id.hasPrefix("kismet.meetup."),
				      let uuid = UUID(uuidString: String(id.dropFirst("kismet.meetup.".count))),
				      let snapshot = store.meetupSnapshots().first(where: { $0.id == uuid })
				else { continue }
				items.append(makeMeetupItem(from: snapshot))
			}
			if !items.isEmpty {
				searchableIndex.indexSearchableItems(items) { _ in
					acknowledgementHandler()
				}
			} else {
				acknowledgementHandler()
			}
		}
	}

	/// Recover full items for SpotlightSearchTool (compact index may omit body text).
	nonisolated func searchableItems(forIdentifiers identifiers: [String]) async -> [CSSearchableItem] {
		await MainActor.run {
			guard let store = memoryStore else { return [] }
			var items: [CSSearchableItem] = []
			for id in identifiers {
				if id == Self.habitsItemIdentifier {
					if let habits = makeHabitsItem(from: store) {
						items.append(habits)
					}
					continue
				}
				guard id.hasPrefix("kismet.meetup."),
				      let uuid = UUID(uuidString: String(id.dropFirst("kismet.meetup.".count))),
				      let snapshot = store.meetupSnapshots().first(where: { $0.id == uuid })
				else { continue }
				items.append(makeMeetupItem(from: snapshot))
			}
			return items
		}
	}
}
