import SwiftUI
import WidgetKit

/// `.accessoryInline` — single-line icon + “N friends nearby · Free now”.
struct NearbyInlineView: View {
	let text: String

	init(text: String) {
		self.text = text
	}

	/// Convenience for snapshot-driven copy.
	init(nearbyCount: Int, freeCount: Int, fallbackHeadline: String = "") {
		if freeCount > 0 {
			let friends = nearbyCount > 0 ? nearbyCount : freeCount
			let noun = friends == 1 ? "friend" : "friends"
			self.text = "\(friends) \(noun) nearby · Free now"
		} else if nearbyCount > 0 {
			let noun = nearbyCount == 1 ? "friend" : "friends"
			self.text = "\(nearbyCount) \(noun) nearby"
		} else if !fallbackHeadline.isEmpty {
			self.text = fallbackHeadline
		} else {
			self.text = "No friends nearby"
		}
	}

	var body: some View {
		Label {
			Text(text)
				.lineLimit(1)
		} icon: {
			Image(systemName: "person.2.fill")
				.widgetAccentable()
		}
	}
}

typealias AccessoryInlineView = NearbyInlineView

#Preview(as: .accessoryInline) {
	FriendAvailabilityWidget()
} timeline: {
	WidgetPreviewData.emptyEntry
	WidgetPreviewData.emptyEntry
}
