//
//  KismetApp.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftData
import SwiftUI

@main
struct KismetApp: App {
	@State private var authSession = AppEnvironment.shared.authSession
	@State private var locationManager = AppEnvironment.shared.locationManager
	@State private var mapFriendsStore = AppEnvironment.shared.mapFriendsStore
	@State private var friendsStore = AppEnvironment.shared.friendsStore
	@State private var locationSharing = AppEnvironment.shared.locationSharing
	@State private var realtimeClient = AppEnvironment.shared.realtimeClient
	@State private var suggestionEngine = AppEnvironment.shared.suggestionEngine
	@State private var pulsePublisher = AppEnvironment.shared.pulsePublisher
	@State private var mapWeather = AppEnvironment.shared.mapWeather
	@State private var weatherObstacles = AppEnvironment.shared.weatherObstacles
	@State private var meetupMemoryStore = AppEnvironment.shared.meetupMemoryStore

	private let meetupContainer = AppEnvironment.shared.meetupModelContainer

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(authSession)
				.environment(locationManager)
				.environment(mapFriendsStore)
				.environment(friendsStore)
				.environment(locationSharing)
				.environment(realtimeClient)
				.environment(suggestionEngine)
				.environment(pulsePublisher)
				.environment(mapWeather)
				.environment(weatherObstacles)
				.environment(meetupMemoryStore)
				.modelContainer(meetupContainer)
				.task {
					await authSession.restore()
				}
		}
	}
}
