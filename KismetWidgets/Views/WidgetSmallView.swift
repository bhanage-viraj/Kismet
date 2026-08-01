import SwiftUI

struct WidgetSmallView: View {
	let card: WidgetAppGroup.Card?

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Label("Kismet", systemImage: "sparkles")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.secondary)

			if let card {
				Text(card.displayName)
					.font(.headline)
					.lineLimit(1)
				Text(card.freeUntilText ?? card.distanceText)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(2)
			} else {
				Text("No one nearby")
					.font(.subheadline.weight(.medium))
				Text("Open Kismet for live suggestions")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.padding(12)
	}
}
