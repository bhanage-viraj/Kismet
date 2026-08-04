import Foundation
import SwiftUI

/// PRD four-state presence. Sealed into LOCATION blobs as `mode`; schedule FREE/BUSY/UNKNOWN
/// remains a calendar signal / legacy fallback only.
enum PresenceState: String, Codable, Hashable, Sendable, CaseIterable {
	case available
	case friendsOnly
	case approximate
	case eclipse

	var title: String {
		switch self {
		case .available: "Available"
		case .friendsOnly: "Friends Only"
		case .approximate: "Approximate"
		case .eclipse: "Eclipse"
		}
	}

	var subtitle: String {
		switch self {
		case .available: "Open to hang"
		case .friendsOnly: "Friends can see you"
		case .approximate: "Rough location only"
		case .eclipse: "Hidden from everyone"
		}
	}

	var systemImage: String {
		switch self {
		case .available: "checkmark.circle.fill"
		case .friendsOnly: "person.2.fill"
		case .approximate: "location.circle.fill"
		case .eclipse: "moon.fill"
		}
	}

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
		case .available: KismetTheme.Bump.available
		case .friendsOnly: KismetTheme.Bump.friendsOnly
		case .approximate: KismetTheme.Bump.approximate
		case .eclipse: KismetTheme.Bump.eclipse
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

	/// Prefer sealed `mode`; fall back to schedule FREE/BUSY/UNKNOWN for legacy blobs.
	static func from(
		payload: LocationPayloadDTO,
		availabilityStatus: AvailabilityStatusDTO
	) -> PresenceState {
		payload.presenceState ?? from(availabilityStatus: availabilityStatus)
	}
}

enum PresenceMapping {
	/// Single bridge so ranking / Siri / widgets don't fork on legacy enums.
	static func presence(for availability: MapAvailability) -> PresenceState {
		PresenceState.from(mapAvailability: availability)
	}
}
