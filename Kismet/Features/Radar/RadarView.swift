import SwiftUI

struct RadarView: View {
	var embedded: Bool = false

	var body: some View {
		Group {
			if embedded {
				content
			} else {
				NavigationStack {
					content
						.navigationTitle("Radar")
				}
			}
		}
	}

	private var content: some View {
		ContentUnavailableView {
			Label("Radar", systemImage: "scope")
		} description: {
			Text("Proximity pulses and who’s free nearby will land here once live friend location is wired up.")
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

#Preview {
	RadarView()
}
