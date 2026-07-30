import SwiftUI

struct PostAuthOnboardingView: View {
	@Environment(AuthSession.self) private var authSession
	@State private var step = 0

	var body: some View {
		NavigationStack {
			Group {
				if step == 0 {
					PermissionsView(onContinue: { step = 1 })
				} else {
					AvailabilitySetupView {
						Task {
							await authSession.completeOnboarding()
						}
					}
				}
			}
			.navigationTitle(step == 0 ? "Permissions" : "Availability")
			.navigationBarTitleDisplayMode(.inline)
		}
	}
}

struct PermissionsView: View {
	var onContinue: () -> Void = {}

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Text("Kismet works best with a few permissions.")
				.font(.title2.weight(.semibold))

			Text("We’ll ask for location and notifications so friends can see when paths cross — always on your terms.")
				.foregroundStyle(.secondary)

			Spacer()

			Button("Continue") {
				onContinue()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
		}
		.padding(24)
	}
}

struct AvailabilitySetupView: View {
	var onFinish: () -> Void = {}

	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Text("Set when you’re usually free.")
				.font(.title2.weight(.semibold))

			Text("You can fine-tune this later. For now, continue to open Kismet.")
				.foregroundStyle(.secondary)

			Spacer()

			Button("Finish setup") {
				onFinish()
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.frame(maxWidth: .infinity)
		}
		.padding(24)
	}
}
