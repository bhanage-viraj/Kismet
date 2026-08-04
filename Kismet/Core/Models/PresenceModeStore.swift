import Foundation
import Observation

/// Source of truth for the user's Presence State.
/// Persists locally and drives E2EE LOCATION publishes via `LocationSharingService`.
@Observable
@MainActor
final class PresenceModeStore {
	private static let defaultsKey = "kismet.presenceMode"

	var state: PresenceState {
		didSet {
			guard state != oldValue else { return }
			UserDefaults.standard.set(state.rawValue, forKey: Self.defaultsKey)
		}
	}

	init(state: PresenceState? = nil) {
		if let state {
			self.state = state
		} else if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
		          let parsed = PresenceState(rawValue: raw) {
			self.state = parsed
		} else {
			self.state = .available
		}
	}

	func select(_ state: PresenceState) {
		self.state = state
	}
}
