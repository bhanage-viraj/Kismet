import Foundation

/// Shared App Group flag flipped by `SetFocusFilterIntent` when a Focus that includes Kismet is active.
enum FocusSocialGate {
	static let blocksSocialKey = "focus.blocksSocial"
	static let labelKey = "focus.label"

	static var blocksSocial: Bool {
		AppGroup.defaults?.bool(forKey: blocksSocialKey) ?? false
	}

	static var label: String? {
		guard blocksSocial else { return nil }
		return AppGroup.defaults?.string(forKey: labelKey) ?? "Focus"
	}

	static func setBlocksSocial(_ value: Bool, label: String? = "Focus") {
		AppGroup.defaults?.set(value, forKey: blocksSocialKey)
		if value {
			AppGroup.defaults?.set(label ?? "Focus", forKey: labelKey)
		} else {
			AppGroup.defaults?.removeObject(forKey: labelKey)
		}
	}
}
