import AppIntents
import Foundation

/// Shared Siri/Shortcuts helpers for sending Pulses (one friend or “them”).
/// `nonisolated` so Ask Siri / search intents can call these off the MainActor.
nonisolated enum PulseSiriActions {
	static let maxRecipients = 3

	static func isPulseQuery(_ raw: String) -> Bool {
		let q = raw.lowercased()
		guard q.contains("pulse") else { return false }
		// Status questions that mention Pulse by accident still go to status.
		if q.contains("how far") || q.contains("where") || q.contains("status") {
			return false
		}
		return true
	}

	static func isPluralPulseQuery(_ raw: String) -> Bool {
		let q = raw.lowercased()
		return q.contains("them")
			|| q.contains("everyone")
			|| q.contains("friends")
			|| q.contains("all")
			|| q.contains("nearby")
	}

	private struct PulseTarget: Sendable {
		var friendID: String
		var displayName: String
		var venueName: String?
		var suggestionCardID: String?
		var reasonCodes: [String]
	}

	/// Pulses one friend, or up to `maxRecipients` nearby free friends when plural.
	static func performPulse(
		friend: FriendEntity? = nil,
		plural: Bool = false
	) async throws -> IntentDialog {
		let targets = await resolveTargets(friend: friend, plural: plural)

		guard !targets.isEmpty else {
			return IntentDialog(stringLiteral: "I couldn't find anyone nearby to Pulse. Open Who's Out to refresh, then try again.")
		}

		let (friends, defaultTitle) = await MainActor.run {
			(AppEnvironment.shared.friendsStore.friends, PulseActivity.coffee.defaultTitle)
		}
		var sentNames: [String] = []
		var lastError: String?

		for target in targets {
			let draft = PulseComposeDraft(
				title: defaultTitle,
				activity: .coffee,
				venueName: target.venueName ?? "",
				venueAddress: "",
				startsAt: Date().addingTimeInterval(3600),
				recipientUserId: target.friendID,
				recipientDisplayName: target.displayName,
				suggestionCardID: target.suggestionCardID
			)

			do {
				_ = try await AppEnvironment.shared.pulsePublisher.send(
					draft: draft,
					senderUserId: KeychainStore.get(.userId),
					friends: friends
				)
				await MainActor.run {
					let env = AppEnvironment.shared
					env.meetupMemoryStore.recordFeedback(
						friendUserId: target.friendID,
						action: .cta,
						reasonCodes: target.reasonCodes
					)
					env.meetupMemoryStore.recordMeetup(
						friendUserId: target.friendID,
						friendDisplayName: target.displayName,
						venueName: target.venueName,
						source: .pulse,
						outcome: .pending
					)
					env.pendingPulseDraft = nil
				}
				sentNames.append(target.displayName)
			} catch {
				lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			}
		}

		guard !sentNames.isEmpty else {
			return IntentDialog(stringLiteral: lastError ?? "Couldn't send that Pulse.")
		}

		if sentNames.count == 1 {
			return IntentDialog(stringLiteral: "Pulse sent to \(sentNames[0]).")
		}
		let list = sentNames.joined(separator: ", ")
		return IntentDialog(stringLiteral: "Pulsed \(sentNames.count) friends: \(list).")
	}

	private static func resolveTargets(
		friend: FriendEntity?,
		plural: Bool
	) async -> [PulseTarget] {
		await MainActor.run {
			let env = AppEnvironment.shared
			let liveCards = env.suggestionEngine.store.cards.filter(\.presence.isSuggestionEligible)

			if let friend {
				if let match = liveCards.first(where: { $0.friendID == friend.id }) {
					return [target(from: match)]
				}
				if let person = env.mapFriendsStore.friends.first(where: { $0.id == friend.id }),
				   person.presenceState.isSuggestionEligible {
					return [
						PulseTarget(
							friendID: person.id,
							displayName: person.displayName,
							venueName: nil,
							suggestionCardID: nil,
							reasonCodes: []
						)
					]
				}
				return [
					PulseTarget(
						friendID: friend.id,
						displayName: friend.displayName,
						venueName: nil,
						suggestionCardID: nil,
						reasonCodes: []
					)
				]
			}

			let freeLive = liveCards.filter { $0.presence == .available || $0.presence == .approximate }
			let livePool = freeLive.isEmpty ? liveCards : freeLive
			if !livePool.isEmpty {
				let picked = plural ? Array(livePool.prefix(maxRecipients)) : Array(livePool.prefix(1))
				return picked.map(target(from:))
			}

			// Cold Siri wake: live suggestion store may be empty — use widget snapshot.
			guard let snapshot = AppGroup.loadSnapshot(), !snapshot.cards.isEmpty else {
				return []
			}
			let freeSnap = snapshot.cards.filter { $0.status == .free || $0.status == .nearby }
			let snapPool = freeSnap.isEmpty ? snapshot.cards : freeSnap
			let picked = plural ? Array(snapPool.prefix(maxRecipients)) : Array(snapPool.prefix(1))
			return picked.map {
				PulseTarget(
					friendID: $0.friendID,
					displayName: $0.displayName,
					venueName: $0.venueName,
					suggestionCardID: $0.id,
					reasonCodes: []
				)
			}
		}
	}

	private static func target(from card: SuggestionCard) -> PulseTarget {
		PulseTarget(
			friendID: card.friendID,
			displayName: card.displayName,
			venueName: card.venueName,
			suggestionCardID: card.id,
			reasonCodes: card.reasonCodes.map(\.rawValue)
		)
	}
}
