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

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(authSession)
				.environment(locationManager)
				.environment(mapFriendsStore)
				.task {
					await authSession.restore()
				}
		}
	}
}
