import Foundation
import SwiftData

enum MeetupModelContainer {
	static let schema = Schema([
		MeetupEvent.self,
		SuggestionFeedback.self,
		LearnedProfileSnapshot.self
	])

	/// On-device only — no CloudKit sync in this milestone.
	static func make() throws -> ModelContainer {
		let configuration = ModelConfiguration(
			"KismetMeetupMemory",
			schema: schema,
			isStoredInMemoryOnly: false,
			cloudKitDatabase: .none
		)
		return try ModelContainer(for: schema, configurations: [configuration])
	}

	static func makeInMemory() throws -> ModelContainer {
		let configuration = ModelConfiguration(
			"KismetMeetupMemoryInMemory",
			schema: schema,
			isStoredInMemoryOnly: true,
			cloudKitDatabase: .none
		)
		return try ModelContainer(for: schema, configurations: [configuration])
	}
}
