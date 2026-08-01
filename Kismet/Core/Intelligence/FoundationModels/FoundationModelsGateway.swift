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
		ranked: [RankedOpportunity]
	) async throws -> PulseSuggestionBundle {
		guard case .available = SystemLanguageModel.default.availability else {
			let message = availabilityMessage() ?? "Model unavailable"
			lastUnavailableReason = message
			throw FoundationModelsGatewayError.unavailable(message)
		}
		lastUnavailableReason = nil

		let tool = FindNearbyVenueTool(coordinate: context.user.coordinate)
		let session = LanguageModelSession(tools: [tool]) {
			Instructions {
				PromptBuilder.instructions
			}
		}
		session.prewarm()

		let prompt = PromptBuilder.prompt(context: context, ranked: ranked)
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
