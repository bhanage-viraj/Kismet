import Foundation
import UIKit

/// Registers the APNs device token with the Spring relay so LOCATION blobs can silent-wake this phone.
enum PushTokenRegistrar {
	private static let lastTokenDefaultsKey = "push.lastUploadedDeviceToken"

	struct TokenBody: Encodable {
		var deviceToken: String
		var platform: String
	}

	struct TokenResponse: Decodable {
		var ok: Bool
	}

	static func registerForRemoteNotifications() {
		DispatchQueue.main.async {
			UIApplication.shared.registerForRemoteNotifications()
		}
	}

	static func upload(deviceToken: Data) async {
		guard KeychainStore.get(.accessToken) != nil else { return }
		let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
		UserDefaults.standard.set(hex, forKey: lastTokenDefaultsKey)
		do {
			let _: TokenResponse = try await APIClient.shared.post(
				"/push/token",
				body: TokenBody(deviceToken: hex, platform: "ios")
			)
		} catch {
			// Non-fatal — significant-change monitoring still covers proximity without push.
		}
	}

	static func unregisterCurrentToken() async {
		guard let hex = UserDefaults.standard.string(forKey: lastTokenDefaultsKey), !hex.isEmpty else {
			return
		}
		do {
			let _: TokenResponse = try await APIClient.shared.request(
				method: "DELETE",
				path: "/push/token",
				body: TokenBody(deviceToken: hex, platform: "ios")
			)
		} catch {
			// Best effort on sign-out.
		}
		UserDefaults.standard.removeObject(forKey: lastTokenDefaultsKey)
	}
}
