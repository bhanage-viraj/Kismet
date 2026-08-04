import SwiftUI

struct RadarView: View {
	var embedded: Bool = false

	var body: some View {
		Group {
			if embedded {
				BumpFlowView()
			} else {
				NavigationStack {
					BumpFlowView()
						.navigationTitle("Radar")
						.navigationBarTitleDisplayMode(.inline)
				}
			}
		}
	}
}

#if DEBUG
#Preview {
	RadarView()
		.environment(AuthSession.previewSignedIn(displayName: "Ada"))
		.environment(FriendsStore.preview())
}
#endif
