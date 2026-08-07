//
//  ContentView.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		RootView()
	}
}

// The preview helpers below are DEBUG-only, so the preview must be too —
// otherwise a Release build fails on symbols that were compiled out.
#if DEBUG
#Preview("Signed in") {
	SignedInPreviewHost()
}

private struct SignedInPreviewHost: View {
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var locationManager = VisitLocationManager()
	@State private var mapFriendsStore = MapFriendsStore()
	@State private var friendsStore = FriendsStore.preview()
	@State private var locationSharing = LocationSharingService()
	@State private var realtimeClient = RealtimeClient()
	@State private var presenceMode = PresenceModeStore(state: .available)
	@State private var friendsOnlyVisibility = FriendsOnlyVisibilityStore()

	var body: some View {
		ContentView()
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
					presenceMode: presenceMode,
					friendsOnlyVisibility: friendsOnlyVisibility
				)
			)
			.environment(realtimeClient)
			.environment(presenceMode)
			.environment(friendsOnlyVisibility)
			.task {
				mapFriendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
			}
	}
}
#endif
