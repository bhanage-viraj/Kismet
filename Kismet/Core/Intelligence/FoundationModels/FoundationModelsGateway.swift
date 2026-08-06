import CoreLocation
import Foundation
import FoundationModels

enum FoundationModelsGatewayError: LocalizedError {
	case unavailable(String)
	case generationFailed(String)

	var errorDescription: String? {
		switch self {
		case .unavailable(let reason): reason
		case .generationFailed(let reason): reason
		}
	}
}

/// Thin wrapper around SystemLanguageModel + LanguageModelSession.
/// iOS 27+: Dynamic Profiles agent (memory → venue → draft). Older OS: single-session legacy path.
@MainActor
final class FoundationModelsGateway {
	private(set) var lastUnavailableReason: String?

	var isAvailable: Bool {
		if case .available = SystemLanguageModel.default.availability {
			return true
		}
		return false
	}

	func availabilityMessage() -> String? {
		switch SystemLanguageModel.default.availability {
		case .available:
			return nil
		case .unavailable(let reason):
			switch reason {
			case .deviceNotEligible:
				return "Apple Intelligence isn’t supported on this device."
			case .appleIntelligenceNotEnabled:
				return "Turn on Apple Intelligence in Settings to unlock smarter suggestions."
			case .modelNotReady:
				return "Apple Intelligence is still downloading. Showing quick suggestions for now."
			@unknown default:
				return "Apple Intelligence isn’t available right now."
			}
		}
	}

	func generateSuggestions(
		context: KismetContext,
		ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState] = [:]
	) async throws -> PulseSuggestionBundle {
		guard case .available = SystemLanguageModel.default.availability else {
			let message = availabilityMessage() ?? "Model unavailable"
			lastUnavailableReason = message
			throw FoundationModelsGatewayError.unavailable(message)
		}
		lastUnavailableReason = nil

		// `#if compiler` only wraps APIs that need a newer SDK.
		// Runtime `#available(iOS 27, *)` is what decides the path on-device.
		#if compiler(>=6.4)
		if #available(iOS 27.0, *) {
			do {
				return try await SuggestionAgentRunner.generate(
					context: context,
					ranked: ranked,
					venueStates: venueStates
				)
			} catch {
				#if DEBUG
				print("Suggestion agent failed, falling back: \(error.localizedDescription)")
				#endif
			}
		}
		#endif

		return try await generateLegacy(context: context, ranked: ranked, venueStates: venueStates)
	}

	private func generateLegacy(
		context: KismetContext,
		ranked: [RankedOpportunity],
		venueStates: [String: VenueResolutionState]
	) async throws -> PulseSuggestionBundle {
		let tool = FindNearbyVenueTool(coordinate: context.user.coordinate)
		let session = LanguageModelSession(tools: [tool]) {
			Instructions {
				PromptBuilder.instructions + """

				Leave pulseMessage and venueName empty — the app drafts the Pulse body from the selected venue.
				"""
			}
		}
		session.prewarm()

		let prompt = PromptBuilder.prompt(context: context, ranked: ranked, venueStates: venueStates)
		do {
			let response = try await session.respond(
				to: prompt,
				generating: PulseSuggestionBundle.self
			)
			return response.content
		} catch {
			throw FoundationModelsGatewayError.generationFailed(error.localizedDescription)
		}
	}
}
