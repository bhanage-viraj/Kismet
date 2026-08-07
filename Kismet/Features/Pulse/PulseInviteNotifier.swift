import Foundation
import UserNotifications

/// Local / remote Pulse alerts so invites surface when the map is not open.
enum PulseInviteNotifier {
	static let categoryId = "pulse.invite"

	static func requestAuthorizationIfNeeded() {
		UNUserNotificationCenter.current().getNotificationSettings { settings in
			guard settings.authorizationStatus == .notDetermined else { return }
			UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
		}
	}

	static func notifyNewPulse(
		blobId: String,
		senderDisplayName: String,
		label: String,
		emoji: String
	) {
		requestAuthorizationIfNeeded()

		let content = UNMutableNotificationContent()
		content.title = "\(emoji) Pulse from \(senderDisplayName)"
		content.body = label.isEmpty ? "Wants to hang out." : label
		content.sound = .default
		content.categoryIdentifier = categoryId
		content.userInfo = [
			"type": "blob.available",
			"kind": "PULSE",
			"blobId": blobId,
			"senderDisplayName": senderDisplayName
		]

		let request = UNNotificationRequest(
			identifier: "pulse.invite.\(blobId)",
			content: content,
			trigger: nil
		)
		UNUserNotificationCenter.current().add(request)
	}

	static func clearPulse(blobId: String) {
		let id = "pulse.invite.\(blobId)"
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
		UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
	}
}
