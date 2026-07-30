import SwiftUI

struct RootView: View {
	@Environment(AuthSession.self) private var authSession

	var body: some View {
		Group {
			switch authSession.phase {
			case .bootstrapping:
				SplashScreenView()
			case .signedOut:
				OnboardingFlowView()
			case .needsOnboarding:
				PostAuthOnboardingView()
			case .signedIn:
				MainTabView()
			}
		}
		.animation(.easeInOut(duration: 0.35), value: authSession.phase)
	}
}

#Preview {
	RootView()
		.environment(AuthSession())
}
