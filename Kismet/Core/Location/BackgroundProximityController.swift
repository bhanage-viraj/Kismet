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
	private let friendsOnlyVisibility: FriendsOnlyVisibilityStore

	private var handleTask: Task<Void, Never>?
	private var lastHandledLocation: CLLocation?
	private let minHandleInterval: TimeInterval = 45
	private let minHandleDistance: CLLocationDistance = 40

	init(
		locationManager: VisitLocationManager,
		locationSharing: LocationSharingService,
		friendsStore: FriendsStore,
		mapFriendsStore: MapFriendsStore,
		presenceMode: PresenceModeStore,
		friendsOnlyVisibility: FriendsOnlyVisibilityStore
	) {
		self.locationManager = locationManager
		self.locationSharing = locationSharing
		self.friendsStore = friendsStore
		self.mapFriendsStore = mapFriendsStore
		self.presenceMode = presenceMode
		self.friendsOnlyVisibility = friendsOnlyVisibility
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

	/// Called from a silent APNs wake when a friend uploaded a LOCATION or PULSE blob.
	@discardableResult
	func handleRemoteWake(userInfo: [AnyHashable: Any]) async -> Bool {
		guard isEnabled else { return false }
		let type = userInfo["type"] as? String
		let kind = (userInfo["kind"] as? String)?.uppercased()
		if let type, type != "blob.available" {
			return false
		}
		if let kind, kind != "LOCATION", kind != "PULSE", kind != "MEETUP" {
			return false
		}

		if kind == "PULSE" || kind == "MEETUP" {
			await friendsStore.refresh()
			await AppEnvironment.shared.pulseInbox.refresh(friends: friendsStore.friends)
			if kind == "MEETUP" {
				let meetups = await MeetupSharingService().consumePendingMeetups(friends: friendsStore.friends)
				for item in meetups {
					await startBackgroundMeetupLiveActivity(
						senderUserId: item.senderUserId,
						payload: item.payload
					)
				}
			}
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
			presence: presenceMode.state,
			friendsOnlyVisibleIds: friendsOnlyVisibility.visibleFriendIds,
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

	private func startBackgroundMeetupLiveActivity(
		senderUserId: String,
		payload: MeetupPayloadDTO
	) async {
		let peerName = friendsStore.friends.first(where: { $0.userId == senderUserId })?.displayName
			?? payload.peerDisplayName
		let youName = AppEnvironment.shared.authSession.preferredDisplayName
		let venueName = payload.venueName ?? payload.title
		let participants: [MeetupActivityAttributes.Participant] = [
			.init(
				id: KeychainStore.get(.userId) ?? "you",
				displayName: youName,
				initials: String(youName.prefix(1)).uppercased(),
				status: .nearby,
				isYou: true
			),
			.init(
				id: senderUserId,
				displayName: peerName,
				initials: String(peerName.prefix(1)).uppercased(),
				status: .free,
				isYou: false
			)
		]
		do {
			_ = try await MeetupLiveActivityController.start(
				meetupID: payload.meetupId,
				title: payload.title,
				venueName: venueName,
				systemImage: payload.systemImage,
				participants: participants,
				venueCoordinate: nil,
				meetAt: payload.meetAt,
				currentLocation: locationManager.userLocation
			)
		} catch {
			// Live Activities may be disabled in background.
		}
	}
}
