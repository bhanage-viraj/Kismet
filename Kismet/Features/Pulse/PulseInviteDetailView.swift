import SwiftUI
import UIKit

/// Invitation detail for an incoming Pulse — hero, plan details, Going / Maybe.
struct PulseInviteDetailView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.dismiss) private var dismiss

	let pulse: IncomingPulse
	var attendees: [Attendee] = []
	var goingCount: Int = 1
	var maybeCount: Int = 0
	var onGoing: () -> Void
	var onMaybe: () -> Void

	struct Attendee: Identifiable, Hashable {
		var id: String
		var displayName: String
		var photo: UIImage? = nil
	}

	private var titleColor: Color { KismetTheme.Insight.titleColor(for: colorScheme) }
	private var bodyColor: Color { KismetTheme.Insight.bodyColor(for: colorScheme) }
	private var cardBg: Color { KismetTheme.Insight.cardBackground(for: colorScheme) }
	private var activity: PulseActivity {
		PulseActivity(rawValue: pulse.payload.activityId ?? "") ?? .coffee
	}

	private var displayedAttendees: [Attendee] {
		if !attendees.isEmpty { return attendees }
		return [
			Attendee(id: pulse.senderUserId, displayName: pulse.senderDisplayName),
		]
	}

	var body: some View {
		ZStack(alignment: .bottom) {
			hero
				.ignoresSafeArea(edges: .top)

			VStack(spacing: 0) {
				Spacer(minLength: 0)
				detailCard
			}
		}
		.background(Color.black.ignoresSafeArea())
	}

	// MARK: - Hero

	private var hero: some View {
		GeometryReader { geo in
			ZStack(alignment: .topLeading) {
				LinearGradient(
					colors: [
						activity.accent.opacity(0.85),
						Color(red: 0.18, green: 0.22, blue: 0.20),
					],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)

				// Soft cafe-like depth without requiring a photo asset.
				RadialGradient(
					colors: [
						Color.white.opacity(0.18),
						Color.clear,
					],
					center: .topTrailing,
					startRadius: 20,
					endRadius: geo.size.width * 0.8
				)

				VStack {
					Spacer()
					HStack {
						Spacer()
						Image(systemName: activity.symbol)
							.font(.system(size: 96, weight: .light))
							.foregroundStyle(.white.opacity(0.18))
							.padding(.trailing, 28)
							.padding(.bottom, 120)
					}
				}

				Button {
					dismiss()
				} label: {
					Image(systemName: "xmark")
						.font(.system(size: 14, weight: .bold))
						.foregroundStyle(.white)
						.frame(width: 32, height: 32)
						.background(.ultraThinMaterial, in: Circle())
				}
				.padding(.leading, 20)
				.padding(.top, 12)
				.accessibilityLabel("Close")
			}
			.frame(width: geo.size.width, height: geo.size.height * 0.48)
		}
	}

	// MARK: - Card

	private var detailCard: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text(pulse.payload.label)
				.font(.system(size: 28, weight: .bold, design: .rounded))
				.foregroundStyle(titleColor)
				.padding(.top, 28)
				.padding(.bottom, 22)

			VStack(alignment: .leading, spacing: 18) {
				infoRow(symbol: "calendar") {
					Text(PulseComposeView.formatWhen(pulse.payload.plannedAt))
						.font(.body.weight(.semibold))
						.foregroundStyle(titleColor)
				}

				infoRow(symbol: "mappin.and.ellipse") {
					VStack(alignment: .leading, spacing: 2) {
						Text(pulse.payload.venueName?.nilIfBlank ?? "Somewhere nearby")
							.font(.body.weight(.semibold))
							.foregroundStyle(titleColor)
						if let address = pulse.payload.venueAddress?.nilIfBlank {
							Text(address)
								.font(.subheadline)
								.foregroundStyle(bodyColor)
						}
					}
				}

				infoRow(symbol: "person.2.fill") {
					VStack(alignment: .leading, spacing: 12) {
						Text("\(goingCount) going · \(maybeCount) maybe")
							.font(.body.weight(.semibold))
							.foregroundStyle(titleColor)

						avatarStack
					}
				}
			}

			Spacer(minLength: 28)

			HStack(spacing: 12) {
				Button(action: onGoing) {
					Text("I'm Going")
						.font(.headline.weight(.bold))
						.frame(maxWidth: .infinity)
						.frame(height: 54)
						.foregroundStyle(.white)
						.background(
							Color(red: 0.12, green: 0.35, blue: 0.28),
							in: RoundedRectangle(cornerRadius: 16, style: .continuous)
						)
				}
				.buttonStyle(.plain)

				Button(action: onMaybe) {
					Text("Maybe")
						.font(.headline.weight(.semibold))
						.frame(maxWidth: .infinity)
						.frame(height: 54)
						.foregroundStyle(titleColor)
						.background(
							RoundedRectangle(cornerRadius: 16, style: .continuous)
								.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
						)
				}
				.buttonStyle(.plain)
			}
			.padding(.bottom, 8)
		}
		.padding(.horizontal, 24)
		.padding(.bottom, 20)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			UnevenRoundedRectangle(
				topLeadingRadius: 28,
				bottomLeadingRadius: 0,
				bottomTrailingRadius: 0,
				topTrailingRadius: 28,
				style: .continuous
			)
			.fill(cardBg)
			.ignoresSafeArea(edges: .bottom)
		)
	}

	private func infoRow<Content: View>(symbol: String, @ViewBuilder content: () -> Content) -> some View {
		HStack(alignment: .top, spacing: 14) {
			Image(systemName: symbol)
				.font(.system(size: 16, weight: .semibold))
				.foregroundStyle(bodyColor)
				.frame(width: 22, height: 22)
				.padding(.top, 2)
			content()
			Spacer(minLength: 0)
		}
	}

	private var avatarStack: some View {
		HStack(spacing: -10) {
			ForEach(Array(displayedAttendees.prefix(4).enumerated()), id: \.element.id) { index, person in
				PresenceAvatar(
					initials: PresenceAvatar.initials(from: person.displayName),
					name: person.displayName,
					status: .available,
					size: 36,
					ringWidth: 2,
					ringGap: 1.5,
					ringTrackColor: cardBg,
					photo: person.photo ?? PresenceAvatar.photo(forUserId: person.id),
					showsStatusDot: false
				)
				.zIndex(Double(4 - index))
			}

			let overflow = max(0, goingCount + maybeCount - min(displayedAttendees.count, 4))
			if overflow > 0 {
				Text("+\(overflow)")
					.font(.caption.weight(.bold))
					.foregroundStyle(titleColor)
					.frame(width: 36, height: 36)
					.background(Color.primary.opacity(0.06), in: Circle())
					.overlay(Circle().strokeBorder(cardBg, lineWidth: 2))
					.padding(.leading, 4)
			}
		}
	}
}

private extension String {
	var nilIfBlank: String? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

#Preview {
	PulseInviteDetailView(
		pulse: IncomingPulse(
			blobId: "blob-1",
			senderUserId: "u1",
			senderDisplayName: "Aarav",
			payload: PulsePayloadDTO(
				pulseId: "p1",
				emoji: "☕",
				label: "Coffee catch-up ☕",
				expiresAt: Date().addingTimeInterval(3600),
				venueName: "Third Wave Coffee",
				createdAt: Date(),
				venueAddress: "Koramangala 4th Block",
				startsAt: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()),
				activityId: "coffee"
			),
			receivedAt: Date()
		),
		attendees: [
			.init(id: "1", displayName: "Aarav"),
			.init(id: "2", displayName: "Maya"),
			.init(id: "3", displayName: "Kai"),
			.init(id: "4", displayName: "Sam"),
		],
		goingCount: 3,
		maybeCount: 2,
		onGoing: {},
		onMaybe: {}
	)
}
