import CoreLocation
import Foundation
import Observation
import SwiftUI
import UIKit

/// Keeps encrypted location publishing alive outside the map session using significant
/// location changes + silent push wakes, then checks friend blobs on-device for proximity.
@Observable
@MainActor
final class BackgroundProximityController {
	private(set) var isEnabled = false
	private(set) var lastProximityCheckAt: Date?
	private(set) var lastErrorMessage: String?

	/// Neighborhood-scale threshold matching significant-change coarseness.
	var proximityRadiusMeters: CLLocationDistance = 800

	private let locationManager: VisitLocationManager
	private let locationSharing: LocationSharingService
	private let friendsStore: FriendsStore
	private let mapFriendsStore: MapFriendsStore

	private var handleTask: Task<Void, Never>?
	private var lastHandledLocation: CLLocation?
	private let minHandleInterval: TimeInterval = 45
	private let minHandleDistance: CLLocationDistance = 40

	init(
		locationManager: VisitLocationManager,
		locationSharing: LocationSharingService,
		friendsStore: FriendsStore,
		mapFriendsStore: MapFriendsStore
	) {
		self.locationManager = locationManager
		self.locationSharing = locationSharing
		self.friendsStore = friendsStore
		self.mapFriendsStore = mapFriendsStore
	}

	func start() {
		guard !isEnabled else { return }
		isEnabled = true
		locationSharing.start()
		NearbyFriendNotifier.requestAuthorizationIfNeeded()
		PushTokenRegistrar.registerForRemoteNotifications()

		locationManager.onLocationUpdate = { [weak self] location in
			self?.handleLocationUpdate(location)
		}

		locationManager.prepareForMapAppearance()
		if let location = locationManager.userLocation {
			handleLocationUpdate(location, force: true)
		}
	}

	func stop() {
		isEnabled = false
		handleTask?.cancel()
		handleTask = nil
		locationManager.onLocationUpdate = nil
		locationManager.tearDownBackgroundMonitoring()
		locationSharing.stop()
		NearbyFriendNotifier.clearCooldowns()
	}

	func handleScenePhase(_ phase: ScenePhase) {
		guard isEnabled else { return }
		switch phase {
		case .active:
			locationManager.applySceneMode(.active)
			PushTokenRegistrar.registerForRemoteNotifications()
			if let location = locationManager.userLocation {
				handleLocationUpdate(location, force: false)
			}
		case .background:
			locationManager.applySceneMode(.background)
		case .inactive:
			break
		@unknown default:
			break
		}
	}

	/// Called from a silent APNs wake when a friend uploaded a LOCATION blob.
	@discardableResult
	func handleRemoteWake(userInfo: [AnyHashable: Any]) async -> Bool {
		guard isEnabled else { return false }
		let type = userInfo["type"] as? String
		let kind = (userInfo["kind"] as? String)?.uppercased()
		if let type, type != "blob.available" {
			return false
		}
		if let kind, kind != "LOCATION" {
			return false
		}

		// Spend a little background budget trying for a fresh fix before distance math.
		if locationManager.isAuthorized {
			locationManager.startUpdating()
			try? await Task.sleep(for: .milliseconds(800))
		}

		guard let origin = locationManager.userLocation else {
			guard !locationManager.isUsingFallbackCoordinate else { return false }
			let coordinate = locationManager.displayCoordinate
			return await refreshAndNotify(
				origin: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
			)
		}
		return await refreshAndNotify(origin: origin)
	}

	private func handleLocationUpdate(_ location: CLLocation, force: Bool = false) {
		guard isEnabled else { return }

		if !force, let lastHandledLocation {
			let moved = location.distance(from: lastHandledLocation)
			let elapsed = lastProximityCheckAt.map { Date().timeIntervalSince($0) } ?? .infinity
			if moved < minHandleDistance, elapsed < minHandleInterval {
				return
			}
		}

		handleTask?.cancel()
		handleTask = Task { [weak self] in
			await self?.publishAndCheckProximity(location: location, force: force)
		}
	}

	private func publishAndCheckProximity(location: CLLocation, force: Bool) async {
		guard !Task.isCancelled, isEnabled else { return }

		if friendsStore.friends.isEmpty {
			await friendsStore.refresh()
		}

		let senderUserId = KeychainStore.get(.userId)
		locationSharing.shareIfNeeded(
			location: location,
			senderUserId: senderUserId,
			friends: friendsStore.friends,
			force: force
		)

		_ = await refreshAndNotify(origin: location)
	}

	@discardableResult
	private func refreshAndNotify(origin: CLLocation) async -> Bool {
		guard !Task.isCancelled, isEnabled else { return false }

		await mapFriendsStore.refresh(around: origin.coordinate)
		guard !Task.isCancelled else { return false }

		lastHandledLocation = origin
		lastProximityCheckAt = Date()
		lastErrorMessage = mapFriendsStore.lastErrorMessage ?? locationSharing.lastErrorMessage

		var notified = false
		for friend in mapFriendsStore.friends where friend.distanceMeters <= proximityRadiusMeters {
			guard friend.presenceState != .eclipse else { continue }
			NearbyFriendNotifier.notifyIfAllowed(
				friendID: friend.id,
				displayName: friend.displayName,
				distanceMeters: friend.distanceMeters
			)
			notified = true
		}
		return notified || mapFriendsStore.lastRefreshedAt != nil
	}
}
