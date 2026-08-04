import CoreLocation
import Foundation
import MapKit
import Observation
import UIKit

enum LocationSceneMode {
	case active
	case background
}

@Observable
@MainActor
final class VisitLocationManager: NSObject {
	private(set) var authorizationStatus: CLAuthorizationStatus
	private(set) var userCoordinate: CLLocationCoordinate2D?
	private(set) var userLocation: CLLocation?
	private(set) var placeName: String?
	private(set) var lastErrorMessage: String?
	private(set) var isUpdating = false
	private(set) var isMonitoringSignificantChanges = false

	/// Invoked on every accepted fix (foreground continuous or background significant-change).
	var onLocationUpdate: ((CLLocation) -> Void)?

	var hasFix: Bool { userCoordinate != nil }

	var isAuthorized: Bool {
		switch authorizationStatus {
		case .authorizedWhenInUse, .authorizedAlways:
			return true
		default:
			return false
		}
	}

	var isAlwaysAuthorized: Bool {
		authorizationStatus == .authorizedAlways
	}

	var needsPermissionPrompt: Bool {
		authorizationStatus == .notDetermined
	}

	var isDenied: Bool {
		authorizationStatus == .denied || authorizationStatus == .restricted
	}

	/// Prefer a live fix; fall back to Koramangala demo seed for Simulator / pre-permission.
	var displayCoordinate: CLLocationCoordinate2D {
		userCoordinate ?? MockFriendsProvider.fallbackCoordinate
	}

	var isUsingFallbackCoordinate: Bool {
		userCoordinate == nil
	}

	var displayPlaceName: String {
		if let placeName, !placeName.isEmpty {
			return placeName
		}
		if isDenied {
			return "Location off"
		}
		if isUsingFallbackCoordinate {
			return "Koramangala, Bengaluru"
		}
		return "Locating…"
	}

	func openSystemSettings() {
		guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
		UIApplication.shared.open(url)
	}

	private let manager = CLLocationManager()
	private var geocodeTask: Task<Void, Never>?
	private var lastGeocodedLocation: CLLocation?
	private let alwaysPromptDefaultsKey = "location.didRequestAlwaysAuthorization"

	override init() {
		authorizationStatus = manager.authorizationStatus
		super.init()
		manager.delegate = self
		manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
		manager.distanceFilter = 15
		manager.pausesLocationUpdatesAutomatically = true
		// Significant-change wakes do not need continuous background GPS; keep this false.
		manager.allowsBackgroundLocationUpdates = false
	}

	func requestWhenInUseAuthorization() {
		guard authorizationStatus == .notDetermined else { return }
		manager.requestWhenInUseAuthorization()
	}

	/// Upgrade path after When In Use — required before significant-change monitoring works reliably.
	func requestAlwaysAuthorizationIfNeeded() {
		authorizationStatus = manager.authorizationStatus
		guard authorizationStatus == .authorizedWhenInUse else { return }
		guard !UserDefaults.standard.bool(forKey: alwaysPromptDefaultsKey) else { return }
		UserDefaults.standard.set(true, forKey: alwaysPromptDefaultsKey)
		manager.requestAlwaysAuthorization()
	}

	func startUpdating() {
		authorizationStatus = manager.authorizationStatus
		guard isAuthorized else {
			if needsPermissionPrompt {
				requestWhenInUseAuthorization()
			}
			return
		}
		isUpdating = true
		manager.startUpdatingLocation()
	}

	func stopUpdating() {
		isUpdating = false
		manager.stopUpdatingLocation()
	}

	/// Battery-friendly background path: cell/Wi‑Fi handoffs wake the app to republish location.
	func startSignificantLocationMonitoring() {
		authorizationStatus = manager.authorizationStatus
		guard isAuthorized else { return }
		guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
		manager.startMonitoringSignificantLocationChanges()
		isMonitoringSignificantChanges = true
	}

	func stopSignificantLocationMonitoring() {
		manager.stopMonitoringSignificantLocationChanges()
		isMonitoringSignificantChanges = false
	}

	/// Foreground: precise continuous GPS. Background: drop continuous, keep significant-change.
	func applySceneMode(_ mode: LocationSceneMode) {
		authorizationStatus = manager.authorizationStatus
		guard isAuthorized else { return }

		switch mode {
		case .active:
			startUpdating()
			requestAlwaysAuthorizationIfNeeded()
			if isAlwaysAuthorized {
				startSignificantLocationMonitoring()
			}
		case .background:
			stopUpdating()
			if isAlwaysAuthorized {
				startSignificantLocationMonitoring()
			}
		}
	}

	func prepareForMapAppearance() {
		authorizationStatus = manager.authorizationStatus
		if KismetRuntime.isXcodePreview {
			// Previews: seed without prompting the location permission dialog.
			return
		}
		if needsPermissionPrompt {
			requestWhenInUseAuthorization()
		} else if isAuthorized {
			startUpdating()
			requestAlwaysAuthorizationIfNeeded()
			if isAlwaysAuthorized {
				startSignificantLocationMonitoring()
			}
		}
	}

	func tearDownBackgroundMonitoring() {
		stopUpdating()
		stopSignificantLocationMonitoring()
	}
}

extension VisitLocationManager: CLLocationManagerDelegate {
	nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		Task { @MainActor in
			authorizationStatus = manager.authorizationStatus
			if isAuthorized {
				startUpdating()
				requestAlwaysAuthorizationIfNeeded()
				if isAlwaysAuthorized {
					startSignificantLocationMonitoring()
				}
			} else if isDenied {
				tearDownBackgroundMonitoring()
			}
		}
	}

	nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard let location = locations.last else { return }
		Task { @MainActor in
			userLocation = location
			userCoordinate = location.coordinate
			lastErrorMessage = nil
			scheduleReverseGeocode(for: location)
			MeetupLiveActivityTracker.handleLocationUpdate(location)
			onLocationUpdate?(location)
		}
	}

	nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		Task { @MainActor in
			lastErrorMessage = error.localizedDescription
		}
	}
}

private extension VisitLocationManager {
	func scheduleReverseGeocode(for location: CLLocation) {
		if let lastGeocodedLocation,
		   lastGeocodedLocation.distance(from: location) < 80,
		   placeName != nil {
			return
		}

		geocodeTask?.cancel()
		geocodeTask = Task { [weak self] in
			guard let self else { return }
			let name = await Self.reverseGeocodePlaceName(for: location)
			guard !Task.isCancelled else { return }
			placeName = name
			lastGeocodedLocation = location
		}
	}

	static func reverseGeocodePlaceName(for location: CLLocation) async -> String? {
		guard let request = MKReverseGeocodingRequest(location: location) else {
			return nil
		}
		do {
			let mapItems = try await request.mapItems
			guard let item = mapItems.first else { return nil }
			if let city = item.addressRepresentations?.cityWithContext {
				return city
			}
			if let shortAddress = item.address?.shortAddress {
				return shortAddress
			}
			return item.name
		} catch {
			return nil
		}
	}
}
