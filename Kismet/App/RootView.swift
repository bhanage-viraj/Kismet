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

#Preview("Signed in") {
	RootPreviewHost()
}

private struct RootPreviewHost: View {
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var locationManager = VisitLocationManager()
	@State private var mapFriendsStore = MapFriendsStore()
	@State private var friendsStore = FriendsStore.preview()
	@State private var locationSharing = LocationSharingService()
	@State private var realtimeClient = RealtimeClient()

	var body: some View {
		RootView()
			.environment(authSession)
			.environment(locationManager)
			.environment(mapFriendsStore)
			.environment(friendsStore)
			.environment(locationSharing)
			.environment(realtimeClient)
			.task {
				mapFriendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
			}
	}
}
