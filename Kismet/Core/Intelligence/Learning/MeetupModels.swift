import Foundation
import SwiftData

enum MeetupSource: String, Codable, Sendable {
	case pulse
	case suggestion
	case manual
}

enum MeetupOutcome: String, Codable, Sendable {
	case completed
	case declined
	case expired
	case unknown
	case pending
}

enum SuggestionFeedbackAction: String, Codable, Sendable {
	case shown
	case dismissed
	case cta
	case up
	case down
}

enum VenueCategory: String, Codable, Sendable, CaseIterable, Hashable {
	case coffee
	case food
	case walk
	case other

	static func infer(from text: String?) -> VenueCategory {
		guard let text, !text.isEmpty else { return .other }
		let lower = text.lowercased()
		if lower.contains("coffee") || lower.contains("cafe") || lower.contains("chai") {
			return .coffee
		}
		if lower.contains("lunch") || lower.contains("dinner") || lower.contains("food")
			|| lower.contains("restaurant") || lower.contains("brunch") {
			return .food
		}
		if lower.contains("walk") || lower.contains("park") || lower.contains("run") {
			return .walk
		}
		return .other
	}
}

@Model
final class MeetupEvent {
	var id: UUID
	var friendUserId: String
	var friendDisplayName: String
	var startedAt: Date
	var endedAt: Date?
	var venueName: String?
	var venueCategoryRaw: String
	var sourceRaw: String
	var outcomeRaw: String

	var venueCategory: VenueCategory {
		get { VenueCategory(rawValue: venueCategoryRaw) ?? .other }
		set { venueCategoryRaw = newValue.rawValue }
	}

	var source: MeetupSource {
		get { MeetupSource(rawValue: sourceRaw) ?? .manual }
		set { sourceRaw = newValue.rawValue }
	}

	var outcome: MeetupOutcome {
		get { MeetupOutcome(rawValue: outcomeRaw) ?? .unknown }
		set { outcomeRaw = newValue.rawValue }
	}

	init(
		id: UUID = UUID(),
		friendUserId: String,
		friendDisplayName: String,
		startedAt: Date = Date(),
		endedAt: Date? = nil,
		venueName: String? = nil,
		venueCategory: VenueCategory = .other,
		source: MeetupSource,
		outcome: MeetupOutcome = .pending
	) {
		self.id = id
		self.friendUserId = friendUserId
		self.friendDisplayName = friendDisplayName
		self.startedAt = startedAt
		self.endedAt = endedAt
		self.venueName = venueName
		self.venueCategoryRaw = venueCategory.rawValue
		self.sourceRaw = source.rawValue
		self.outcomeRaw = outcome.rawValue
	}
}

@Model
final class SuggestionFeedback {
	var id: UUID
	var friendUserId: String
	var createdAt: Date
	var actionRaw: String
	var reasonCodesJoined: String

	var action: SuggestionFeedbackAction {
		get { SuggestionFeedbackAction(rawValue: actionRaw) ?? .shown }
		set { actionRaw = newValue.rawValue }
	}

	var reasonCodes: [String] {
		get {
			reasonCodesJoined
				.split(separator: "|")
				.map(String.init)
				.filter { !$0.isEmpty }
		}
		set {
			reasonCodesJoined = newValue.joined(separator: "|")
		}
	}

	init(
		id: UUID = UUID(),
		friendUserId: String,
		createdAt: Date = Date(),
		action: SuggestionFeedbackAction,
		reasonCodes: [String] = []
	) {
		self.id = id
		self.friendUserId = friendUserId
		self.createdAt = createdAt
		self.actionRaw = action.rawValue
		self.reasonCodesJoined = reasonCodes.joined(separator: "|")
	}
}

@Model
final class LearnedProfileSnapshot {
	var updatedAt: Date
	var summaryText: String
	var topFriendIdsJoined: String
	var preferredHoursJoined: String
	var preferredCategoriesJoined: String

	var topFriendIds: [String] {
		get {
			topFriendIdsJoined
				.split(separator: "|")
				.map(String.init)
				.filter { !$0.isEmpty }
		}
		set { topFriendIdsJoined = newValue.joined(separator: "|") }
	}

	var preferredHours: [Int] {
		get {
			preferredHoursJoined
				.split(separator: "|")
				.compactMap { Int($0) }
		}
		set {
			preferredHoursJoined = newValue.map(String.init).joined(separator: "|")
		}
	}

	var preferredCategories: [String] {
		get {
			preferredCategoriesJoined
				.split(separator: "|")
				.map(String.init)
				.filter { !$0.isEmpty }
		}
		set { preferredCategoriesJoined = newValue.joined(separator: "|") }
	}

	init(
		updatedAt: Date = Date(),
		summaryText: String = "",
		topFriendIds: [String] = [],
		preferredHours: [Int] = [],
		preferredCategories: [String] = []
	) {
		self.updatedAt = updatedAt
		self.summaryText = summaryText
		self.topFriendIdsJoined = topFriendIds.joined(separator: "|")
		self.preferredHoursJoined = preferredHours.map(String.init).joined(separator: "|")
		self.preferredCategoriesJoined = preferredCategories.joined(separator: "|")
	}
}
