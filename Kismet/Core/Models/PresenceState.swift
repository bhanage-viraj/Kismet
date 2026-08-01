import Foundation
import SwiftUI

/// PRD four-state presence. Bridges legacy free/busy/unknown until clients emit this natively.
enum PresenceState: String, Codable, Hashable, Sendable, CaseIterable {
	case available
	case friendsOnly
	case approximate
	case eclipse

	/// Shown on map / suggestion surfaces (Eclipse is hidden entirely).
	var isSurfaceVisible: Bool {
		self != .eclipse
	}

	/// Eligible for Intelligence ranking (Approximate may suggest without precise ETA).
	var isSuggestionEligible: Bool {
		switch self {
		case .available, .friendsOnly, .approximate: true
		case .eclipse: false
		}
	}

	var showsPreciseLocation: Bool {
		switch self {
		case .available, .friendsOnly: true
		case .approximate, .eclipse: false
		}
	}

	var statusColor: Color {
		switch self {
		case .available: KismetTheme.Status.free
		case .friendsOnly: KismetTheme.Status.busy
		case .approximate: KismetTheme.Status.unknown
		case .eclipse: KismetTheme.Status.away
		}
	}

	var mapAvailability: MapAvailability {
		switch self {
		case .available: .free
		case .friendsOnly: .busy
		case .approximate, .eclipse: .unknown
		}
	}

	static func from(mapAvailability: MapAvailability) -> PresenceState {
		switch mapAvailability {
		case .free: .available
		case .busy: .friendsOnly
		case .unknown: .approximate
		}
	}

	static func from(availabilityStatus: AvailabilityStatusDTO) -> PresenceState {
		from(mapAvailability: availabilityStatus.mapAvailability)
	}
}

enum PresenceMapping {
	/// Single bridge so ranking / Siri / widgets don't fork on legacy enums.
	static func presence(for availability: MapAvailability) -> PresenceState {
		PresenceState.from(mapAvailability: availability)
	}
}
