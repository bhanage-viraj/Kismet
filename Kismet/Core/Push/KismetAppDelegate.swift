import UIKit
import UserNotifications

/// Bridges APNs registration + silent/alert wakes into the shared app environment.
final class KismetAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		UNUserNotificationCenter.current().delegate = self
		PulseInviteNotifier.requestAuthorizationIfNeeded()
		return true
	}

	func application(
		_ application: UIApplication,
		didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
	) {
		Task {
			await PushTokenRegistrar.upload(deviceToken: deviceToken)
		}
	}

	func application(
		_ application: UIApplication,
		didFailToRegisterForRemoteNotificationsWithError error: Error
	) {
		// Simulator / missing Push capability — proximity still works via significant-change.
		#if DEBUG
		print("APNs registration failed: \(error.localizedDescription)")
		#endif
	}

	func application(
		_ application: UIApplication,
		didReceiveRemoteNotification userInfo: [AnyHashable: Any],
		fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
	) {
		Task { @MainActor in
			let changed = await AppEnvironment.shared.backgroundProximity.handleRemoteWake(userInfo: userInfo)
			completionHandler(changed ? .newData : .noData)
		}
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification,
		withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
	) {
		let userInfo = notification.request.content.userInfo
		Task { @MainActor in
			_ = await AppEnvironment.shared.backgroundProximity.handleRemoteWake(userInfo: userInfo)
		}
		// Show the banner even while the app is open (map Pulse banner may not be visible).
		completionHandler([.banner, .sound, .badge])
	}

	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse,
		withCompletionHandler completionHandler: @escaping () -> Void
	) {
		let userInfo = response.notification.request.content.userInfo
		Task { @MainActor in
			_ = await AppEnvironment.shared.backgroundProximity.handleRemoteWake(userInfo: userInfo)
			completionHandler()
		}
	}
}
