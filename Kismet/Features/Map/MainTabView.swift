import SwiftUI

struct MainTabView: View {
	@Environment(AuthSession.self) private var authSession

	var body: some View {
		TabView {
			Tab("Map", systemImage: "map") {
				NavigationStack {
					VStack(spacing: 12) {
						Text("Map")
							.font(.largeTitle.bold())
						Text("Signed in as \(authSession.user?.displayName ?? authSession.user?.email ?? "you")")
							.foregroundStyle(.secondary)
					}
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.navigationTitle("Kismet")
				}
			}

			Tab("Activity", systemImage: "bolt.heart") {
				NavigationStack {
					Text("Activity")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.navigationTitle("Activity")
				}
			}

			Tab("More", systemImage: "ellipsis.circle") {
				MoreView()
			}
		}
	}
}

#Preview {
	MainTabView()
		.environment(AuthSession())
}
