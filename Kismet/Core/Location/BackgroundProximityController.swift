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
	private let presenceMode: PresenceModeStore

	private var handleTask: Task<Void, Never>?
	private var lastHandledLocation: CLLocation?
	private var isAppActive = true
	private let minHandleInterval: TimeInterval = 45
	private let minHandleDistance: CLLocationDistance = 40

	init(
		locationManager: VisitLocationManager,
		locationSharing: LocationSharingService,
		friendsStore: FriendsStore,
		mapFriendsStore: MapFriendsStore,
		presenceMode: PresenceModeStore
	) {
		self.locationManager = locationManager
		self.locationSharing = locationSharing
		self.friendsStore = friendsStore
		self.mapFriendsStore = mapFriendsStore
		self.presenceMode = presenceMode
	}

	func start() {
		guard !isEnabled else { return }
		isEnabled = true
		locationSharing.start()
		NearbyFriendNotifier.requestAuthorizationIfNeeded()
		PulseInviteNotifier.requestAuthorizationIfNeeded()
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
			isAppActive = true
			AppEnvironment.shared.pulseInbox.postsNotificationsForNewPulses = false
			locationManager.applySceneMode(.active)
			PushTokenRegistrar.registerForRemoteNotifications()
			if let location = locationManager.userLocation {
				// Foreground map session owns friend/blob refreshes; only re-publish location.
				publishLocation(location, force: false)
			}
		case .background:
			isAppActive = false
			AppEnvironment.shared.pulseInbox.postsNotificationsForNewPulses = true
			locationManager.applySceneMode(.background)
		case .inactive:
			break
		@unknown default:
			break
		}
	}

	/// Called from a silent APNs wake when a friend uploaded a LOCATION or PULSE blob.
	@discardableResult
	func handleRemoteWake(userInfo: [AnyHashable: Any]) async -> Bool {
		guard isEnabled else { return false }
		let type = userInfo["type"] as? String
		let kind = (userInfo["kind"] as? String)?.uppercased()
		if let type, type != "blob.available" {
			return false
		}
		if let kind, kind != "LOCATION", kind != "PULSE" {
			return false
		}

		if kind == "PULSE" {
			let inbox = AppEnvironment.shared.pulseInbox
			let wasPosting = inbox.postsNotificationsForNewPulses
			// Alert pushes already show a system banner — only post a richer local
			// notification when this was a silent wake without an alert payload.
			inbox.postsNotificationsForNewPulses = !Self.remoteNotificationHasAlert(userInfo)
			await friendsStore.refresh()
			await inbox.refresh(friends: friendsStore.friends)
			inbox.postsNotificationsForNewPulses = wasPosting || !isAppActive
			return true
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

		// While the map session is foregrounded it already polls / refreshes.
		// Background path only publishes location and skips duplicate network work.
		if isAppActive {
			publishLocation(location, force: force)
			return
		}

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

	private func publishLocation(_ location: CLLocation, force: Bool) {
		if friendsStore.friends.isEmpty {
			Task { await friendsStore.refresh() }
		}
		locationSharing.shareIfNeeded(
			location: location,
			senderUserId: KeychainStore.get(.userId),
			friends: friendsStore.friends,
			presence: presenceMode.state,
			force: force
		)
	}

	private func publishAndCheckProximity(location: CLLocation, force: Bool) async {
		guard !Task.isCancelled, isEnabled else { return }

		if friendsStore.friends.isEmpty {
			await friendsStore.refresh()
		}

		publishLocation(location, force: force)
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
			guard friend.presenceState.isSurfaceVisible else { continue }
			NearbyFriendNotifier.notifyIfAllowed(
				friendID: friend.id,
				displayName: friend.displayName,
				distanceMeters: friend.distanceMeters,
				showsPreciseDistance: friend.presenceState.showsPreciseLocation
			)
			notified = true
		}
		return notified || mapFriendsStore.lastRefreshedAt != nil
	}

	private static func remoteNotificationHasAlert(_ userInfo: [AnyHashable: Any]) -> Bool {
		guard let aps = userInfo["aps"] as? [String: Any] else { return false }
		return aps["alert"] != nil
	}
}
