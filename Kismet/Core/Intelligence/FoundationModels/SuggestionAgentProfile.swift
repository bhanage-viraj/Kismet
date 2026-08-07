import CoreLocation
import Foundation
import FoundationModels
import Observation

/// Phases for the on-device suggestion agent (Dynamic Profiles on iOS 27+).
enum SuggestionAgentPhase: String, Sendable {
	case memory
	case venue
	case draft
}

@Observable
@MainActor
final class SuggestionAgentState {
	var phase: SuggestionAgentPhase = .memory
}

#if compiler(>=6.4)
import CoreSpotlight

/// Dynamic Profiles agent: memory search → venue grounding → Pulse draft.
/// Compiled only with the iOS 27 / Swift 6.4 toolchain; runtime-gated with `#available(iOS 27, *)`.
@available(iOS 27.0, *)
struct SuggestionAgentProfile: LanguageModelSession.DynamicProfile {
	var state: SuggestionAgentState
	var venueCoordinate: CLLocationCoordinate2D

	var body: some LanguageModelSession.DynamicProfile {
		switch state.phase {
		case .memory:
			LanguageModelSession.Profile {
				Instructions {
					"""
					You are Kismet's memory scout. Search meetup hangout history for habits \
					relevant to the candidate friends. Do not invent meetups. Summarize only \
					what the search returns (usual people, spots, hours).
					"""
				}
				SpotlightSearchTool(
					configuration: SpotlightSearchTool.Configuration(
						sources: [
							.coreSpotlight(
								CoreSpotlightSource(
									searchableIndexDelegate: MeetupSpotlightIndexer.shared
								)
							)
						],
						guide: .focused(.items)
					)
				)
			}
		case .venue:
			LanguageModelSession.Profile {
				Instructions {
					"""
					You are Kismet's venue scout. When a shared interest or usual spot implies \
					a place type, call findNearbyVenue for a real nearby spot. Never invent venue names.
					"""
				}
				FindNearbyVenueTool(coordinate: venueCoordinate)
			}
		case .draft:
			LanguageModelSession.Profile {
				Instructions {
					PromptBuilder.instructions + """

					Leave pulseMessage and venueName empty — the app drafts the Pulse body from the selected venue.
					"""
				}
			}
			.toolCallingMode(.disallowed)
		}
	}
}

@available(iOS 27.0, *)
enum SuggestionAgentRunner {
	static func generate(
		context: KismetContext,
		ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState] = [:]
	) async throws -> PulseSuggestionBundle {
		let state = SuggestionAgentState()
		let profile = SuggestionAgentProfile(
			state: state,
			venueCoordinate: context.user.coordinate
		)
		let session = LanguageModelSession(profile: profile)
		session.prewarm()

		let basePrompt = PromptBuilder.prompt(
			context: context,
			ranked: ranked,
			venueStates: venueStates
		)

		state.phase = .memory
		_ = try await session.respond(
			to: """
			\(basePrompt)

			First, search meetup memory for hangout habits that relate to these candidates. \
			Briefly note any useful habitual times or usual spots — do not invent history.
			"""
		)

		state.phase = .venue
		let needsToolBackup = ranked.contains { venueStates[$0.friend.id] == nil || venueStates[$0.friend.id] == .empty }
		if needsToolBackup {
			_ = try await session.respond(
				to: """
				If a venue would help any candidate that lacks grounded_venue, use findNearbyVenue. \
				Otherwise say no venue needed.
				"""
			)
		} else {
			_ = try await session.respond(
				to: "Grounded venues are already provided. Confirm no invented places; say ready to draft."
			)
		}

		state.phase = .draft
		let response = try await session.respond(
			to: """
			\(basePrompt)

			Return structured suggestions now. Leave pulseMessage and venueName empty — \
			the app drafts the Pulse body from the selected grounded venue.
			""",
			generating: PulseSuggestionBundle.self
		)
		return response.content
	}
}
#endif
