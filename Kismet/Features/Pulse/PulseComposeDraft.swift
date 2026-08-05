import Foundation
import SwiftUI

/// Quick-pick activities shown on the Pulse compose screen.
enum PulseActivity: String, CaseIterable, Identifiable, Sendable, Hashable {
	case coffee
	case walk
	case badminton
	case movies
	case more

	var id: String { rawValue }

	var title: String {
		switch self {
		case .coffee: "Coffee"
		case .walk: "Walk"
		case .badminton: "Badminton"
		case .movies: "Movies"
		case .more: "More"
		}
	}

	var symbol: String {
		switch self {
		case .coffee: "cup.and.saucer.fill"
		case .walk: "figure.walk"
		case .badminton: "figure.badminton"
		case .movies: "film.fill"
		case .more: "ellipsis"
		}
	}

	var accent: Color {
		switch self {
		case .coffee: Color(red: 0.96, green: 0.55, blue: 0.28)
		case .walk: Color(red: 0.30, green: 0.72, blue: 0.48)
		case .badminton: Color(red: 0.92, green: 0.32, blue: 0.28)
		case .movies: Color(red: 0.35, green: 0.55, blue: 0.92)
		case .more: Color(red: 0.55, green: 0.55, blue: 0.58)
		}
	}

	var defaultTitle: String {
		switch self {
		case .coffee: "Coffee catch-up ☕"
		case .walk: "Quick walk 🚶"
		case .badminton: "Badminton?"
		case .movies: "Movie night 🎬"
		case .more: "Hang out?"
		}
	}

	var emoji: String {
		switch self {
		case .coffee: "☕"
		case .walk: "🚶"
		case .badminton: "🏸"
		case .movies: "🎬"
		case .more: "👋"
		}
	}
}

/// Editable draft for the "What's the plan?" compose screen.
struct PulseComposeDraft: Identifiable, Hashable, Sendable {
	var id = UUID()
	var title: String
	var activity: PulseActivity
	var venueName: String
	var venueAddress: String
	var startsAt: Date
	var recipientUserId: String
	var recipientDisplayName: String
	var suggestionCardID: String?

	static func from(card: SuggestionCard) -> PulseComposeDraft {
		let activity = PulseActivity.allCases.first {
			card.ctaTitle.localizedCaseInsensitiveContains($0.title)
				|| (card.venueName?.localizedCaseInsensitiveContains($0.title) == true)
		} ?? .coffee

		let defaultStart = Calendar.current.nextDate(
			after: Date(),
			matching: DateComponents(hour: 17, minute: 0),
			matchingPolicy: .nextTime
		) ?? Date().addingTimeInterval(3600)

		return PulseComposeDraft(
			title: card.pulseMessage?.nilIfEmpty
				?? card.ctaTitle.nilIfEmpty
				?? activity.defaultTitle,
			activity: activity,
			venueName: card.venueName ?? "",
			venueAddress: "",
			startsAt: defaultStart,
			recipientUserId: card.friendID,
			recipientDisplayName: card.displayName,
			suggestionCardID: card.id
		)
	}
}

private extension String {
	var nilIfEmpty: String? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}
