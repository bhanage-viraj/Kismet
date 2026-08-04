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
	@UIApplicationDelegateAdaptor(KismetAppDelegate.self) private var appDelegate
	@Environment(\.scenePhase) private var scenePhase

	@State private var authSession = AppEnvironment.shared.authSession
	@State private var locationManager = AppEnvironment.shared.locationManager
	@State private var mapFriendsStore = AppEnvironment.shared.mapFriendsStore
	@State private var friendsStore = AppEnvironment.shared.friendsStore
	@State private var locationSharing = AppEnvironment.shared.locationSharing
	@State private var backgroundProximity = AppEnvironment.shared.backgroundProximity
	@State private var realtimeClient = AppEnvironment.shared.realtimeClient
	@State private var suggestionEngine = AppEnvironment.shared.suggestionEngine
	@State private var pulsePublisher = AppEnvironment.shared.pulsePublisher
	@State private var mapWeather = AppEnvironment.shared.mapWeather
	@State private var weatherObstacles = AppEnvironment.shared.weatherObstacles
	@State private var meetupMemoryStore = AppEnvironment.shared.meetupMemoryStore
	@State private var presenceMode = AppEnvironment.shared.presenceMode

	private let meetupContainer = AppEnvironment.shared.meetupModelContainer

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(authSession)
				.environment(locationManager)
				.environment(mapFriendsStore)
				.environment(friendsStore)
				.environment(locationSharing)
				.environment(backgroundProximity)
				.environment(realtimeClient)
				.environment(suggestionEngine)
				.environment(pulsePublisher)
				.environment(mapWeather)
				.environment(weatherObstacles)
				.environment(meetupMemoryStore)
				.environment(presenceMode)
				.modelContainer(meetupContainer)
				.task {
					await authSession.restore()
					syncBackgroundProximity()
					// Warm Friends Map from real App Group data, or an empty location-only map.
					if let snapshot = AppGroup.loadSnapshot() {
						WidgetMapSnapshotRenderer.refresh(from: snapshot)
					} else {
						SuggestionSnapshotWriter.persistEmptyMap(
							userCoordinate: locationManager.userCoordinate
						)
					}
				}
				.onChange(of: authSession.phase) { _, _ in
					syncBackgroundProximity()
				}
				.onChange(of: scenePhase) { _, newPhase in
					backgroundProximity.handleScenePhase(newPhase)
				}
		}
	}

	@MainActor
	private func syncBackgroundProximity() {
		if authSession.phase == .signedIn {
			backgroundProximity.start()
		} else {
			backgroundProximity.stop()
		}
	}
}
