import SwiftUI

struct MoreView: View {
	@Environment(AuthSession.self) private var authSession
	var embedded: Bool = false

	var body: some View {
		Group {
			if embedded {
				listContent
			} else {
				NavigationStack {
					listContent
						.navigationTitle("More")
				}
			}
		}
	}

	private var listContent: some View {
		List {
			Section("Account") {
				if let user = authSession.user {
					LabeledContent("Name", value: user.displayName ?? "—")
					LabeledContent("Email", value: user.email ?? "—")
				} else {
					LabeledContent("Name", value: "—")
					LabeledContent("Email", value: "—")
				}
				Button("Sign Out", role: .destructive) {
					Task {
						await authSession.signOut()
					}
				}
			}
		}
		.scrollContentBackground(embedded ? .hidden : .automatic)
		.listStyle(.insetGrouped)
	}
}

#Preview {
	MoreView()
		.environment(AuthSession())
}
