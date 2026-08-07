import SwiftUI

struct OnboardingFlowView: View {
	@Environment(AuthSession.self) private var authSession
	/// Skip the animated splash when we already showed it during bootstrap restore.
	@State private var step: Step = .howItWorks

	var body: some View {
		ZStack {
			switch step {
			case .splash:
				SplashScreenView()
					.transition(.opacity)
					.task {
						try? await Task.sleep(for: .seconds(1.2))
						guard !Task.isCancelled else { return }
						withAnimation(.easeInOut(duration: 0.45)) {
							step = .howItWorks
						}
					}

			case .howItWorks:
				PermissionsView {
					withAnimation(.easeInOut(duration: 0.45)) {
						step = .signIn
					}
				}
				.transition(.opacity)

			case .signIn:
				AuthView { result in
					Task {
						await authSession.handleSignInCompletion(result)
					}
				}
				.task {
					// Start waking a sleeping free-tier Render instance while the
					// user reads the sign-in screen / taps Apple.
					await APIClient.shared.wakeServer()
				}
				.overlay {
					if authSession.isSigningIn {
						ZStack {
							Color.black.opacity(0.25).ignoresSafeArea()
							VStack(spacing: 14) {
								ProgressView()
									.controlSize(.large)
								Text("Connecting…")
									.font(.subheadline.weight(.semibold))
									.foregroundStyle(.primary)
								Text("The server may take a moment to wake up.")
									.font(.caption)
									.foregroundStyle(.secondary)
									.multilineTextAlignment(.center)
							}
							.padding(24)
							.frame(maxWidth: 260)
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
			}
		}
		.ignoresSafeArea()
	}

	private enum Step {
		case splash
		case howItWorks
		case signIn
	}
}

#Preview {
	OnboardingFlowView()
		.environment(AuthSession())
}
