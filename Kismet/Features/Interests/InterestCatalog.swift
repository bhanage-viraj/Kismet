import SwiftUI

struct InterestItem: Identifiable, Hashable, Sendable {
	let id: String
	let name: String
	let symbol: String
	let color: Color
}

enum InterestCatalog {
	static let primary: [InterestItem] = [
		InterestItem(id: "coffee", name: "Coffee", symbol: "cup.and.saucer.fill", color: .orange),
		InterestItem(id: "music", name: "Music", symbol: "music.note", color: .red),
		InterestItem(id: "art", name: "Art", symbol: "paintpalette.fill", color: .green),
		InterestItem(id: "badminton", name: "Badminton", symbol: "figure.badminton", color: .yellow),
		InterestItem(id: "football", name: "Football", symbol: "soccerball", color: .blue),
		InterestItem(id: "gym", name: "Gym", symbol: "dumbbell.fill", color: .orange),
		InterestItem(id: "movies", name: "Movies", symbol: "film.fill", color: .mint),
		InterestItem(id: "coding", name: "Coding", symbol: "chevron.left.forwardslash.chevron.right", color: .indigo),
		InterestItem(id: "travel", name: "Travel", symbol: "airplane", color: .red),
	]

	static let more: [InterestItem] = [
		InterestItem(id: "reading", name: "Reading", symbol: "book.fill", color: .blue),
		InterestItem(id: "food", name: "Food", symbol: "fork.knife", color: .orange),
		InterestItem(id: "nature", name: "Nature", symbol: "leaf.fill", color: .green),
		InterestItem(id: "gaming", name: "Gaming", symbol: "gamecontroller.fill", color: .purple),
		InterestItem(id: "photography", name: "Photos", symbol: "camera.fill", color: .cyan),
		InterestItem(id: "wellness", name: "Wellness", symbol: "heart.fill", color: .pink),
	]

	static var all: [InterestItem] { primary + more }

	static func item(id: String) -> InterestItem? {
		all.first { $0.id == id }
	}

	static func displayName(for id: String) -> String {
		item(id: id)?.name ?? id.capitalized
	}

	/// Maps hangout venue categories to catalog interest IDs.
	static func interestID(for category: VenueCategory) -> String? {
		switch category {
		case .coffee: return "coffee"
		case .food: return "food"
		case .walk: return "nature"
		case .other: return nil
		}
	}
}
