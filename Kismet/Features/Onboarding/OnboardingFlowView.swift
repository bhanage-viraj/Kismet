import SwiftUI

struct OnboardingFlowView: View {
	@Environment(AuthSession.self) private var authSession
	@State private var isShowingAuth = false

	var body: some View {
		ZStack {
			if isShowingAuth {
				AuthView { result in
					Task {
						await authSession.handleSignInCompletion(result)
					}
				}
				.overlay {
					if authSession.isSigningIn {
						ZStack {
							Color.black.opacity(0.25).ignoresSafeArea()
							ProgressView()
								.controlSize(.large)
								.padding(24)
								.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
						}
					}
				}
				.alert(
					"Sign in failed",
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
				.transition(.opacity)
			} else {
				SplashScreenView()
					.transition(.opacity)
					.task {
						try? await Task.sleep(for: .seconds(1.2))
						guard !Task.isCancelled else { return }
						withAnimation(.easeInOut(duration: 0.45)) {
							isShowingAuth = true
						}
					}
			}
		}
		.ignoresSafeArea()
	}
}

#Preview {
	OnboardingFlowView()
		.environment(AuthSession())
}
