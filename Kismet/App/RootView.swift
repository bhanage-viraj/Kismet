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

// The preview helpers below are DEBUG-only, so the preview must be too —
// otherwise a Release build fails on symbols that were compiled out.
#if DEBUG
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
	@State private var suggestionEngine = SuggestionEngine()
	@State private var pulsePublisher = PulsePublisher()
	@State private var presenceMode = PresenceModeStore(state: .available)

	var body: some View {
		RootView()
			.environment(authSession)
			.environment(locationManager)
			.environment(mapFriendsStore)
			.environment(friendsStore)
			.environment(locationSharing)
			.environment(
				BackgroundProximityController(
					locationManager: locationManager,
					locationSharing: locationSharing,
					friendsStore: friendsStore,
					mapFriendsStore: mapFriendsStore,
					presenceMode: presenceMode
				)
			)
			.environment(realtimeClient)
			.environment(suggestionEngine)
			.environment(pulsePublisher)
			.environment(presenceMode)
			.task {
				mapFriendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
			}
	}
}
#endif
