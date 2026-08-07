import SwiftUI

struct AIContextInsightsView: View {
	@Environment(\.colorScheme) private var colorScheme

	let cards: [SuggestionCard]
	var statusMessage: String?
	var interestSuggestions: [String] = []
	var showsHeader: Bool = true
	var onSelectFriend: (SuggestionCard) -> Void = { _ in }
	var onCTA: (SuggestionCard) -> Void = { _ in }
	var onDismiss: (SuggestionCard) -> Void = { _ in }
	var onFeedback: (SuggestionCard, SuggestionFeedbackAction) -> Void = { _, _ in }
	var onAppearCard: (SuggestionCard) -> Void = { _ in }
	var onAcceptInterest: (String) -> Void = { _ in }
	var onDismissInterest: (String) -> Void = { _ in }

	var body: some View {
		VStack(spacing: 0) {
			if showsHeader {
				HStack(spacing: 6) {
					Image(systemName: "sparkles")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(KismetTheme.Status.free)

					Text("Suggestions")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(KismetTheme.Insight.titleColor(for: colorScheme))

					Spacer(minLength: 0)
				}
				.padding(.horizontal, 20)
				.padding(.top, 6)
				.padding(.bottom, 12)
			}

			if let statusMessage, !statusMessage.isEmpty, cards.isEmpty {
				ContentUnavailableView(
					"No nearby context yet",
					systemImage: "sparkles",
					description: Text(statusMessage)
				)
				.frame(maxWidth: .infinity, minHeight: 120)
				.padding(.horizontal, 16)
			} else if cards.isEmpty, interestSuggestions.isEmpty {
				ContentUnavailableView(
					"No nearby context yet",
					systemImage: "sparkles",
					description: Text("When friends are around, Who's Out will surface the best moments to connect.")
				)
				.frame(maxWidth: .infinity, minHeight: 120)
				.padding(.horizontal, 16)
			} else {
				ScrollView {
					LazyVStack(spacing: 12) {
						if let statusMessage, !statusMessage.isEmpty, cards.isEmpty {
							Text(statusMessage)
								.font(.caption)
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .leading)
						}

						if let interestID = interestSuggestions.first {
							InterestSuggestionChip(
								interestID: interestID,
								onAccept: { onAcceptInterest(interestID) },
								onDismiss: { onDismissInterest(interestID) }
							)
						}

						ForEach(cards) { card in
							InsightCard(
								card: card,
								onSelect: { onSelectFriend(card) },
								onCTA: { onCTA(card) },
								onDismiss: { onDismiss(card) },
								onFeedback: { action in onFeedback(card, action) }
							)
							.onAppear { onAppearCard(card) }
						}
					}
					.padding(.horizontal, 16)
					.padding(.top, 2)
					.padding(.bottom, 20)
				}
				.scrollIndicators(.visible)
				.scrollBounceBehavior(.basedOnSize)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
	}
}

private struct InterestSuggestionChip: View {
	let interestID: String
	var onAccept: () -> Void
	var onDismiss: () -> Void

	private var name: String {
		InterestCatalog.displayName(for: interestID)
	}

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: InterestCatalog.item(id: interestID)?.symbol ?? "sparkles")
				.foregroundStyle(InterestCatalog.item(id: interestID)?.color ?? .orange)
			VStack(alignment: .leading, spacing: 2) {
				Text("Add \(name) to interests?")
					.font(.subheadline.weight(.semibold))
				Text("From your recent hangouts")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
			Button("Add", action: onAccept)
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
			Button(action: onDismiss) {
				Image(systemName: "xmark")
			}
			.buttonStyle(.borderless)
			.accessibilityLabel("Dismiss interest suggestion")
		}
		.padding(12)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
	}
}

private struct InsightCard: View {
	@Environment(\.colorScheme) private var colorScheme

	let card: SuggestionCard
	var onSelect: () -> Void
	var onCTA: () -> Void
	var onDismiss: () -> Void
	var onFeedback: (SuggestionFeedbackAction) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .center, spacing: 12) {
				Button(action: onSelect) {
					HStack(spacing: 10) {
						avatar

						VStack(alignment: .leading, spacing: 2) {
							Text(card.displayName)
								.font(.body.weight(.semibold))
								.foregroundStyle(KismetTheme.Insight.titleColor(for: colorScheme))
								.lineLimit(1)

							Text(card.formattedDistance)
								.font(.caption)
								.foregroundStyle(KismetTheme.Insight.bodyColor(for: colorScheme))
								.lineLimit(1)
						}

						Spacer(minLength: 0)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)

				Button(action: onCTA) {
					HStack(spacing: 6) {
						Image(systemName: card.ctaSystemImage)
							.font(.caption.weight(.semibold))
						Text(card.ctaTitle)
							.font(.caption.weight(.semibold))
							.lineLimit(1)
					}
					.padding(.horizontal, 12)
					.padding(.vertical, 10)
					.foregroundStyle(KismetTheme.Insight.ctaForeground(for: card.availability))
					.background(
						KismetTheme.Insight.ctaBackground(for: card.availability),
						in: Capsule()
					)
				}
				.buttonStyle(.plain)
				.fixedSize(horizontal: true, vertical: false)
			}

			if !card.factChips.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach(card.factChips, id: \.self) { chip in
							Text(chip)
								.font(.caption2.weight(.medium))
								.padding(.horizontal, 8)
								.padding(.vertical, 5)
								.background(.quaternary.opacity(0.5), in: Capsule())
						}
					}
				}
			}

			Button(action: onSelect) {
				VStack(alignment: .leading, spacing: 4) {
					Text(card.reason)
						.font(.subheadline)
						.foregroundStyle(KismetTheme.Insight.bodyColor(for: colorScheme))
						.multilineTextAlignment(.leading)
						.lineLimit(3)

					if let venue = card.venueName {
						Text(venueDisplayLabel(venue))
							.font(.caption.weight(.semibold))
							.foregroundStyle(KismetTheme.Status.free)
					}

					if let draft = card.pulseMessage, !draft.isEmpty {
						Text("Draft: \"\(draft)\"")
							.font(.caption)
							.foregroundStyle(.secondary)
							.lineLimit(2)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)

			HStack(spacing: 16) {
				Button {
					onFeedback(.up)
				} label: {
					Label("Helpful", systemImage: "hand.thumbsup")
						.font(.caption.weight(.medium))
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)

				Button {
					onFeedback(.down)
				} label: {
					Label("Not now", systemImage: "hand.thumbsdown")
						.font(.caption.weight(.medium))
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)

				Spacer(minLength: 0)

				Button(action: onDismiss) {
					Text("Dismiss")
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(14)
		.background(
			KismetTheme.Insight.cardBackground(for: colorScheme),
			in: RoundedRectangle(cornerRadius: KismetTheme.Insight.cardCornerRadius, style: .continuous)
		)
	}

	private func venueDisplayLabel(_ venue: String) -> String {
		if let label = card.venueDisplayETALabel, !label.isEmpty {
			return "\(venue) · \(label)"
		}
		if let minutes = card.venueETAMinutes {
			return "\(venue) · \(minutes) min"
		}
		return venue
	}

	private var avatar: some View {
		ZStack(alignment: .bottomTrailing) {
			Image(systemName: "person.crop.circle.fill")
				.resizable()
				.scaledToFit()
				.foregroundStyle(.white)
				.padding(8)
				.frame(
					width: KismetTheme.Insight.cardAvatarSize,
					height: KismetTheme.Insight.cardAvatarSize
				)
				.background(
					KismetTheme.Map.ring(for: card.availability).gradient,
					in: Circle()
				)

			Circle()
				.fill(card.presence.statusColor)
				.frame(width: 10, height: 10)
				.overlay {
					Circle().stroke(
						KismetTheme.Insight.cardBackground(for: colorScheme),
						lineWidth: 2
					)
				}
				.offset(x: 1, y: 1)
		}
	}
}

#Preview("Interest chip") {
	AIContextInsightsView(
		cards: FallbackComposer.cards(
			from: OpportunityRanker().rank(context: previewContext)
		),
		interestSuggestions: ["coffee", "nature"]
	)
	.preferredColorScheme(.light)
}

#Preview("Interest chip only") {
	AIContextInsightsView(
		cards: [],
		interestSuggestions: ["food"]
	)
	.preferredColorScheme(.light)
}

#Preview("Light") {
	AIContextInsightsView(
		cards: FallbackComposer.cards(
			from: OpportunityRanker().rank(
				context: previewContext
			)
		),
		interestSuggestions: ["coffee"]
	)
	.preferredColorScheme(.light)
}

#Preview("Dark") {
	AIContextInsightsView(
		cards: FallbackComposer.cards(
			from: OpportunityRanker().rank(
				context: previewContext
			)
		),
		interestSuggestions: ["nature"]
	)
	.preferredColorScheme(.dark)
}

private var previewContext: KismetContext {
	let people = MockFriendsProvider.friends(around: MockFriendsProvider.fallbackCoordinate)
	return KismetContext(
		generatedAt: Date(),
		user: UserContextSlice(
			userId: "me",
			displayName: "You",
			interests: ["coffee"],
			coordinate: MockFriendsProvider.fallbackCoordinate,
			placeName: "Koramangala",
			freeUntil: nil,
			isBusyNow: false
		),
		friends: people.map {
			FriendPresence(
				id: $0.id,
				displayName: $0.displayName,
				coordinate: $0.coordinate,
				presence: $0.presenceState,
				distanceMeters: $0.distanceMeters,
				sharedInterests: $0.sharedInterests,
				freeUntil: nil,
				freeFrom: nil,
				lastSeenAt: nil,
				locationAccuracy: nil
			)
		},
		calendar: CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: nil),
		motion: MotionSlice(activity: .walking),
		focus: FocusSlice(blocksSocial: false, label: nil),
		weather: .unknown,
		learned: .empty
	)
}
