import SwiftUI

struct MoreView: View {
	@Environment(AuthSession.self) private var authSession

	var body: some View {
		NavigationStack {
			List {
				Section("Account") {
					if let user = authSession.user {
						LabeledContent("Name", value: user.displayName ?? "—")
						LabeledContent("Email", value: user.email ?? "—")
					}
					Button("Sign Out", role: .destructive) {
						Task {
							await authSession.signOut()
						}
					}
				}
			}
			.navigationTitle("More")
		}
	}
}

#Preview {
	MoreView()
		.environment(AuthSession())
}
