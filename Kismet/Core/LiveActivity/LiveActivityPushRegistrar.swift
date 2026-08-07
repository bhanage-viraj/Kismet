import Foundation

/// Registers ActivityKit push tokens and relays ContentState to the peer's Live Activity.
enum LiveActivityPushRegistrar {
	struct TokenBody: Encodable {
		var meetupId: String
		var pushToken: String
		var bundleId: String
	}

	struct UpdateBody: Encodable {
		var meetupId: String
		var etaText: String
		var distanceText: String
		var progress: Double
		var isEnded: Bool
		var isExpanded: Bool
		var event: String
	}

	struct OkResponse: Decodable {
		var ok: Bool
	}

	static func uploadToken(meetupId: String, pushToken: Data) async {
		guard KeychainStore.get(.accessToken) != nil else { return }
		let hex = pushToken.map { String(format: "%02.2hhx", $0) }.joined()
		do {
			let _: OkResponse = try await APIClient.shared.post(
				"/push/live-activity",
				body: TokenBody(
					meetupId: meetupId,
					pushToken: hex,
					bundleId: Bundle.main.bundleIdentifier ?? ""
				)
			)
		} catch {
			// Non-fatal — local Live Activity still updates on-device.
		}
	}

	static func pushContentState(
		meetupId: String,
		etaText: String,
		distanceText: String,
		progress: Double,
		isEnded: Bool,
		isExpanded: Bool,
		event: String = "update"
	) async {
		guard KeychainStore.get(.accessToken) != nil else { return }
		do {
			let _: OkResponse = try await APIClient.shared.post(
				"/push/live-activity/update",
				body: UpdateBody(
					meetupId: meetupId,
					etaText: etaText,
					distanceText: distanceText,
					progress: progress,
					isEnded: isEnded,
					isExpanded: isExpanded,
					event: event
				)
			)
		} catch {
			// Best effort peer sync.
		}
	}
}
