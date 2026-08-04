import Foundation
import UserNotifications

/// Posts a local notification when another device invites this phone to Bump.
enum BumpInviteNotifier {
	static let categoryId = "bump.invite"
	static let acceptActionId = "bump.accept"
	static let declineActionId = "bump.decline"

	static func requestAuthorizationIfNeeded() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			guard settings.authorizationStatus == .notDetermined else { return }
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
		}
	}

	static func registerCategories() {
		let accept = UNNotificationAction(
			identifier: acceptActionId,
			title: "Accept",
			options: [.foreground]
		)
		let decline = UNNotificationAction(
			identifier: declineActionId,
			title: "Not now",
			options: [.destructive]
		)
		let category = UNNotificationCategory(
			identifier: categoryId,
			actions: [accept, decline],
			intentIdentifiers: [],
			options: []
		)
		UNUserNotificationCenter.current().setNotificationCategories([category])
	}

	static func notifyIncomingInvite(from displayName: String) {
		requestAuthorizationIfNeeded()
		registerCategories()

		let content = UNMutableNotificationContent()
		content.title = "Bump request"
		content.body = "\(displayName) wants to connect nearby."
		content.sound = .default
		content.categoryIdentifier = categoryId
		content.userInfo = ["peerDisplayName": displayName]

		let request = UNNotificationRequest(
			identifier: "bump.invite.\(displayName)",
			content: content,
			trigger: nil
		)
		UNUserNotificationCenter.current().add(request)
	}

	static func clearInvite(from displayName: String) {
		UNUserNotificationCenter.current()
			.removeDeliveredNotifications(withIdentifiers: ["bump.invite.\(displayName)"])
		UNUserNotificationCenter.current()
			.removePendingNotificationRequests(withIdentifiers: ["bump.invite.\(displayName)"])
	}
}
