import CoreLocation
import Foundation
import UserNotifications

/// Local alerts when a friend decrypts within proximity after a background location wake.
enum NearbyFriendNotifier {
	private static let cooldownDefaultsKey = "nearby.friend.notification.cooldowns"
	private static let cooldownInterval: TimeInterval = 2 * 60 * 60

	static func requestAuthorizationIfNeeded() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			guard settings.authorizationStatus == .notDetermined else { return }
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
		}
	}

	static func notifyIfAllowed(
		friendID: String,
		displayName: String,
		distanceMeters: CLLocationDistance,
		showsPreciseDistance: Bool = true
	) {
		guard shouldNotify(friendID: friendID) else { return }
		requestAuthorizationIfNeeded()

		let content = UNMutableNotificationContent()
		content.title = "Friend nearby"
		if showsPreciseDistance {
			content.body = "\(displayName) is about \(Self.formattedDistance(distanceMeters)) away."
		} else {
			content.body = "\(displayName) is nearby."
		}
		content.sound = .default
		content.userInfo = ["friendUserId": friendID]

		let request = UNNotificationRequest(
			identifier: "nearby.friend.\(friendID)",
			content: content,
			trigger: nil
		)
		UNUserNotificationCenter.current().add(request)
		markNotified(friendID: friendID)
	}

	static func clearCooldowns() {
		UserDefaults.standard.removeObject(forKey: cooldownDefaultsKey)
	}

	private static func shouldNotify(friendID: String) -> Bool {
		let cooldowns = UserDefaults.standard.dictionary(forKey: cooldownDefaultsKey) as? [String: Double] ?? [:]
		guard let last = cooldowns[friendID] else { return true }
		return Date().timeIntervalSince1970 - last >= cooldownInterval
	}

	private static func markNotified(friendID: String) {
		var cooldowns = UserDefaults.standard.dictionary(forKey: cooldownDefaultsKey) as? [String: Double] ?? [:]
		cooldowns[friendID] = Date().timeIntervalSince1970
		UserDefaults.standard.set(cooldowns, forKey: cooldownDefaultsKey)
	}

	private static func formattedDistance(_ meters: CLLocationDistance) -> String {
		if meters < 1_000 {
			return "\(max(1, Int(meters.rounded()))) m"
		}
		let km = meters / 1_000
		return String(format: "%.1f km", km)
	}
}
