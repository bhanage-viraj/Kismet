import UIKit

/// Bridges APNs registration + silent wake into the shared app environment.
final class KismetAppDelegate: NSObject, UIApplicationDelegate {
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
}
