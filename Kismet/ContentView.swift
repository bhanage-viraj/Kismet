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

#Preview("Signed in") {
	SignedInPreviewHost()
}

private struct SignedInPreviewHost: View {
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var locationManager = VisitLocationManager()
	@State private var friendsStore = MapFriendsStore()

	var body: some View {
		ContentView()
			.environment(authSession)
			.environment(locationManager)
			.environment(friendsStore)
			.task {
				friendsStore.refresh(around: MockFriendsProvider.fallbackCoordinate)
			}
	}
}
