//
//  KismetApp.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftUI

@main
struct KismetApp: App {
	@State private var authSession = AppEnvironment.shared.authSession
	@State private var locationManager = AppEnvironment.shared.locationManager
	@State private var mapFriendsStore = AppEnvironment.shared.mapFriendsStore
	@State private var friendsStore = AppEnvironment.shared.friendsStore
	@State private var locationSharing = AppEnvironment.shared.locationSharing
	@State private var realtimeClient = AppEnvironment.shared.realtimeClient

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(authSession)
				.environment(locationManager)
				.environment(mapFriendsStore)
				.environment(friendsStore)
				.environment(locationSharing)
				.environment(realtimeClient)
				.task {
					await authSession.restore()
				}
		}
	}
}
