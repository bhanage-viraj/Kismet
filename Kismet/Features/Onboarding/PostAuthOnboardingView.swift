import SwiftUI

struct PostAuthOnboardingView: View {
	@Environment(AuthSession.self) private var authSession
	@State private var step: Step = .interests

	var body: some View {
		ZStack {
			switch step {
			case .interests:
				InterestsView { interests in
					Task {
						if await authSession.saveInterests(interests) {
							withAnimation(.easeInOut(duration: 0.45)) {
								step = .availability
							}
						}
					}
				}
				.transition(.opacity)

			case .availability:
				AvailabilitySetupView(isSaving: authSession.isSavingOnboarding) { availability in
					Task {
						await authSession.completeOnboarding(availability)
					}
				}
				.transition(.opacity)
			}
		}
		.overlay {
			if authSession.isSavingOnboarding && step == .interests {
				ZStack {
					Color.black.opacity(0.22).ignoresSafeArea()
					ProgressView()
						.controlSize(.large)
						.padding(24)
						.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
				}
			}
		}
		.alert(
			"Couldn’t save your setup",
			isPresented: Binding(
				get: { authSession.lastErrorMessage != nil },
				set: { if !$0 { authSession.clearError() } }
			)
		) {
			Button("OK", role: .cancel) {
				authSession.clearError()
			}
		} message: {
			Text(authSession.lastErrorMessage ?? "")
		}
	}

	private enum Step: Equatable {
		case interests
		case availability
		}
}
