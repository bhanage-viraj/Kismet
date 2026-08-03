//
//  KismetApp.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftData
import SwiftUI
import WidgetKit

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
					// Drop leftover preview/demo widget seeds, then warm the map cache from real data only.
					if let snapshot = AppGroup.loadSnapshot() {
						WidgetMapSnapshotRenderer.refresh(from: snapshot)
					} else {
						WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.mapWidgetKind)
						WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
						WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.meetupWidgetKind)
					}
				}
		}
	}
}
