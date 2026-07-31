import SwiftUI

struct AIContextInsightsView: View {
	@Environment(\.colorScheme) private var colorScheme

	let friends: [MapPerson]
	var showsHeader: Bool = true
	var onSelectFriend: (MapPerson) -> Void = { _ in }
	var onCTA: (MapPerson) -> Void = { _ in }

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

			if friends.isEmpty {
				ContentUnavailableView(
					"No nearby context yet",
					systemImage: "sparkles",
					description: Text("When friends are around, Kismet will surface the best moments to connect.")
				)
				.frame(maxWidth: .infinity, minHeight: 120)
				.padding(.horizontal, 16)
			} else {
				ScrollView {
					LazyVStack(spacing: 12) {
						ForEach(friends) { friend in
							InsightCard(
								person: friend,
								onSelect: { onSelectFriend(friend) },
								onCTA: { onCTA(friend) }
							)
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

private struct InsightCard: View {
	@Environment(\.colorScheme) private var colorScheme

	let person: MapPerson
	var onSelect: () -> Void
	var onCTA: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .center, spacing: 12) {
				Button(action: onSelect) {
					HStack(spacing: 10) {
						avatar

						VStack(alignment: .leading, spacing: 2) {
							Text(person.displayName)
								.font(.body.weight(.semibold))
								.foregroundStyle(KismetTheme.Insight.titleColor(for: colorScheme))
								.lineLimit(1)

							Text(person.formattedDistance)
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
						Image(systemName: person.ctaSystemImage)
							.font(.caption.weight(.semibold))
						Text(person.ctaTitle)
							.font(.caption.weight(.semibold))
							.lineLimit(1)
					}
					.padding(.horizontal, 12)
					.padding(.vertical, 10)
					.foregroundStyle(KismetTheme.Insight.ctaForeground(for: person.availability))
					.background(
						KismetTheme.Insight.ctaBackground(for: person.availability),
						in: Capsule()
					)
				}
				.buttonStyle(.plain)
				.fixedSize(horizontal: true, vertical: false)
			}

			Button(action: onSelect) {
				Text(person.insightSummary)
					.font(.subheadline)
					.foregroundStyle(KismetTheme.Insight.bodyColor(for: colorScheme))
					.multilineTextAlignment(.leading)
					.lineLimit(3)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.buttonStyle(.plain)
		}
		.padding(14)
		.background(
			KismetTheme.Insight.cardBackground(for: colorScheme),
			in: RoundedRectangle(cornerRadius: KismetTheme.Insight.cardCornerRadius, style: .continuous)
		)
	}

	private var avatar: some View {
		ZStack(alignment: .bottomTrailing) {
			Image(systemName: person.accentSystemImage)
				.resizable()
				.scaledToFit()
				.foregroundStyle(.white)
				.padding(8)
				.frame(
					width: KismetTheme.Insight.cardAvatarSize,
					height: KismetTheme.Insight.cardAvatarSize
				)
				.background(
					KismetTheme.Map.ring(for: person.availability).gradient,
					in: Circle()
				)

			Circle()
				.fill(person.availability.statusColor)
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

#Preview("Light") {
	AIContextInsightsView(friends: MockFriendsProvider.friends(around: MockFriendsProvider.fallbackCoordinate))
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	AIContextInsightsView(friends: MockFriendsProvider.friends(around: MockFriendsProvider.fallbackCoordinate))
		.preferredColorScheme(.dark)
}
