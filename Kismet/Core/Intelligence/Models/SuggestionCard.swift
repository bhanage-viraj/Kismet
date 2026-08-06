import CoreLocation
import Foundation

struct SuggestionCard: Identifiable, Sendable {
	var id: String
	var friendID: String
	var displayName: String
	var coordinate: CLLocationCoordinate2D
	var availability: MapAvailability
	var presence: PresenceState
	var distanceMeters: CLLocationDistance
	var reason: String
	var reasonCodes: [ExplainCode]
	var factChips: [String]
	var ctaTitle: String
	var ctaSystemImage: String
	var venueName: String?
	var venueETAMinutes: Int?
	var confidence: Double
	var urgency: SuggestionUrgency
	var isModelGenerated: Bool
	/// Optional draft Pulse body from the Intelligence Layer (not sent until user/Siri confirms).
	var pulseMessage: String? = nil
	/// Optional JPEG/PNG bytes for the friend avatar. When set, widgets persist this into the App Group.
	var avatarImageData: Data? = nil

	/// Full MapKit candidate set for compose picker (Phase 3).
	var venueCandidates: GroundedVenueCandidates? = nil
	/// Currently selected venue (defaults to suggested).
	var selectedVenue: GroundedVenue? = nil
	var venueResolution: VenueResolutionState = .empty
	var venueCoordinate: CLLocationCoordinate2D? = nil
	/// Informational distance/ETA label (e.g. "5 min walk", "350 m").
	var venueDisplayETALabel: String? = nil
	/// Snapshot used to rewrite the Pulse draft when the user switches venues.
	var draftHints: PulseDraftHints? = nil

	var formattedDistance: String {
		if !presence.showsPreciseLocation { return "Nearby" }
		if distanceMeters < 1000 {
			return "\(Int(distanceMeters.rounded())) m away"
		}
		return String(format: "%.1f km away", distanceMeters / 1000)
	}

	/// Apply a user picker selection; updates display fields + context-aware Pulse draft.
	mutating func selectVenue(_ venue: GroundedVenue) {
		selectedVenue = venue
		venueName = venue.name
		venueETAMinutes = venue.displayETAMinutes
		venueCoordinate = venue.coordinate
		venueDisplayETALabel = venue.displayETALabel
		pulseMessage = PulseMessageComposer.draft(
			updatingFrom: pulseMessage,
			venue: venue,
			hints: draftHints
		)
	}

	/// Rebuild a suggestion card from an App Group widget snapshot (Siri warm path).
	static func fromAppGroup(_ card: AppGroup.Card) -> SuggestionCard {
		let presence: PresenceState = {
			if let raw = card.presenceRaw, let value = PresenceState(rawValue: raw) {
				return value
			}
			switch card.status {
			case .free: return .available
			case .busy: return .friendsOnly
			case .nearby: return .approximate
			}
		}()
		let availability: MapAvailability = {
			if let raw = card.availabilityRaw, let value = MapAvailability(rawValue: raw) {
				return value
			}
			switch presence {
			case .available: return .free
			case .friendsOnly: return .busy
			case .approximate, .eclipse: return .unknown
			}
		}()
		let coordinate = CLLocationCoordinate2D(
			latitude: card.latitude ?? 0,
			longitude: card.longitude ?? 0
		)
		let chips: [String] = {
			var values: [String] = []
			if let freeUntilText = card.freeUntilText, !freeUntilText.isEmpty {
				values.append(freeUntilText)
			}
			if !card.distanceText.isEmpty {
				values.append(card.distanceText)
			}
			return values
		}()

		return SuggestionCard(
			id: card.id,
			friendID: card.friendID,
			displayName: card.displayName,
			coordinate: coordinate,
			availability: availability,
			presence: presence,
			distanceMeters: card.distanceMeters ?? 0,
			reason: card.reason,
			reasonCodes: [],
			factChips: chips,
			ctaTitle: card.ctaTitle.isEmpty ? "Send a Pulse" : card.ctaTitle,
			ctaSystemImage: card.ctaSystemImage ?? "wave.3.right",
			venueName: card.venueName,
			venueETAMinutes: nil,
			confidence: 0.5,
			urgency: presence == .available ? .now : .soon,
			isModelGenerated: false,
			pulseMessage: card.pulseMessage,
			venueCoordinate: nil
		)
	}

	/// Minimal eligible card when Confirm Pulse runs after the in-memory store was cleared.
	static func fromPulseDraft(_ draft: PulseDraft, snapshotCard: AppGroup.Card? = nil) -> SuggestionCard {
		if let snapshotCard {
			var card = SuggestionCard.fromAppGroup(snapshotCard)
			if card.pulseMessage?.isEmpty != false {
				card.pulseMessage = draft.message
			}
			if card.venueName == nil {
				card.venueName = draft.venueName
			}
			return card
		}

		return SuggestionCard(
			id: draft.suggestionCardID ?? draft.friendID,
			friendID: draft.friendID,
			displayName: draft.displayName,
			coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
			availability: .free,
			presence: .available,
			distanceMeters: 0,
			reason: "Pulse draft",
			reasonCodes: [],
			factChips: [],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: draft.venueName,
			venueETAMinutes: nil,
			confidence: 0.4,
			urgency: .now,
			isModelGenerated: false,
			pulseMessage: draft.message
		)
	}
}

enum SuggestionUrgency: String, Sendable, Hashable {
	case now
	case soon
	case later
}
