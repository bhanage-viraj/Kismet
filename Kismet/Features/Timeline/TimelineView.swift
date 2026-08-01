import SwiftUI

struct TimelineView: View {
	var embedded: Bool = false

	var body: some View {
		Group {
			if embedded {
				content
			} else {
				NavigationStack {
					content
						.navigationTitle("Timeline")
				}
			}
		}
	}

	private var content: some View {
		ContentUnavailableView {
			Label("Timeline", systemImage: "calendar")
		} description: {
			Text("Meetup moments and shared plans will show up here as the story of your week.")
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

#Preview {
	TimelineView()
}
