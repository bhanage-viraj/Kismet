import SwiftUI

struct WidgetMediumView: View {
	let cards: [WidgetAppGroup.Card]

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label("Suggestions", systemImage: "sparkles")
				.font(.caption.weight(.semibold))
				.foregroundStyle(.secondary)

			if cards.isEmpty {
				Text("No nearby opportunities right now")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				ForEach(cards.prefix(2)) { card in
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							Text(card.displayName)
								.font(.subheadline.weight(.semibold))
							Text(card.reason)
								.font(.caption2)
								.foregroundStyle(.secondary)
								.lineLimit(1)
						}
						Spacer(minLength: 8)
						Text(card.distanceText)
							.font(.caption2.weight(.medium))
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.padding(14)
	}
}
