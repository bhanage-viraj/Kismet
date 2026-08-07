import CoreLocation
import MapKit
import SwiftUI

/// Selection state for the optional Pulse venue picker.
/// Suggested is always available when candidates exist; user may pick an alternative.
struct PulseComposeSelection: Equatable {
	var candidates: GroundedVenueCandidates
	var selectedID: String

	var suggested: GroundedVenue { candidates.suggested }

	var selected: GroundedVenue {
		if suggested.id == selectedID { return suggested }
		return candidates.alternatives.first(where: { $0.id == selectedID }) ?? suggested
	}

	var isUsingSuggested: Bool { selectedID == suggested.id }

	init(candidates: GroundedVenueCandidates) {
		self.candidates = candidates
		self.selectedID = candidates.suggested.id
	}

	mutating func select(_ venue: GroundedVenue) {
		guard candidates.all.contains(where: { $0.id == venue.id }) else { return }
		selectedID = venue.id
	}

	/// Venue locked into the Pulse at send time (defaults to suggested if never changed).
	func lockedVenue() -> GroundedVenue { selected }
}

/// Shared coral accent for Pulse compose controls (activity chips, venue picker, Send).
enum PulseComposeAccent {
	static let solid = Color(red: 0.98, green: 0.42, blue: 0.34)

	static let gradient = LinearGradient(
		colors: [
			Color(red: 1.00, green: 0.52, blue: 0.32),
			Color(red: 0.98, green: 0.38, blue: 0.36),
		],
		startPoint: .topLeading,
		endPoint: .bottomTrailing
	)
}

/// Horizontal activity chips — suggested first, then alternatives (same pattern as venues).
struct ActivityPickerChipRow: View {
	@Environment(\.colorScheme) private var colorScheme
	var candidates: GroundedActivityCandidates
	@Binding var selected: PulseActivity
	var onSelect: (PulseActivity) -> Void

	private var titleColor: Color { KismetTheme.Insight.titleColor(for: colorScheme) }

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				ForEach(candidates.all, id: \.self) { activity in
					activityChip(activity)
				}
			}
			.padding(.vertical, 2)
		}
	}

	@ViewBuilder
	private func activityChip(_ activity: PulseActivity) -> some View {
		let isSelected = selected == activity
		let isSuggested = activity == candidates.suggested

		Button {
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
			onSelect(activity)
		} label: {
			HStack(spacing: 8) {
				Image(systemName: activity.symbol)
					.font(.subheadline.weight(.semibold))
				Text(activity.title)
					.font(.subheadline.weight(.semibold))
				if isSuggested {
					Text("Suggested")
						.font(.caption2.weight(.bold))
						.padding(.horizontal, 6)
						.padding(.vertical, 2)
						.background(PulseComposeAccent.solid.opacity(0.18), in: Capsule())
				}
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 10)
			.foregroundStyle(isSelected ? Color.white : titleColor)
			.background {
				if isSelected {
					Capsule().fill(PulseComposeAccent.gradient)
				} else {
					Capsule()
						.fill(colorScheme == .dark
							? Color(red: 0.20, green: 0.20, blue: 0.21)
							: Color.white)
						.overlay {
							Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
						}
				}
			}
		}
		.buttonStyle(.plain)
	}
}

/// Horizontal venue cards — styled to match Pulse compose (coral accent + field cards).
struct VenuePickerChipRow: View {
	@Binding var selection: PulseComposeSelection
	@Environment(\.colorScheme) private var colorScheme
	var onShowDetails: ((GroundedVenue) -> Void)? = nil

	private let cardWidth: CGFloat = 148
	private let cardHeight: CGFloat = 108
	private let cornerRadius: CGFloat = 18

	/// Same coral used by Pulse compose Send / activity selection.
	private var accent: Color { PulseComposeAccent.solid }

	private var accentGradient: LinearGradient { PulseComposeAccent.gradient }

	private var fieldBg: Color {
		colorScheme == .dark
			? Color(red: 0.20, green: 0.20, blue: 0.21)
			: Color.white
	}

	private var titleColor: Color { KismetTheme.Insight.titleColor(for: colorScheme) }
	private var bodyColor: Color { KismetTheme.Insight.bodyColor(for: colorScheme) }

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 12) {
					ForEach(selection.candidates.all) { venue in
						venueCard(venue)
					}
				}
				.padding(.horizontal, 24)
				.padding(.vertical, 4)
			}

			if selection.isUsingSuggested {
				HStack(spacing: 6) {
					Image(systemName: "sparkles")
						.font(.caption.weight(.semibold))
					Text("Closest to both of you")
						.font(.caption.weight(.medium))
				}
				.foregroundStyle(accent)
				.padding(.horizontal, 24)
				.transition(.opacity.combined(with: .move(edge: .top)))
			}

			if let note = selection.selected.suitabilityNote {
				Text(note)
					.font(.caption2)
					.foregroundStyle(bodyColor)
					.padding(.horizontal, 24)
			}
		}
		.animation(.snappy(duration: 0.22), value: selection.isUsingSuggested)
		.animation(.snappy(duration: 0.22), value: selection.selectedID)
	}

	@ViewBuilder
	private func venueCard(_ venue: GroundedVenue) -> some View {
		let isSelected = selection.selectedID == venue.id
		let isSuggested = venue.id == selection.suggested.id

		Button {
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
			withAnimation(.snappy(duration: 0.22)) {
				selection.select(venue)
			}
		} label: {
			VStack(alignment: .leading, spacing: 0) {
				HStack(alignment: .top) {
					Image(systemName: "mappin.and.ellipse")
						.font(.caption.weight(.semibold))
						.foregroundStyle(isSelected ? Color.white.opacity(0.95) : accent.opacity(0.85))

					Spacer(minLength: 0)

					if isSelected {
						Image(systemName: "checkmark.circle.fill")
							.font(.body)
							.foregroundStyle(.white)
							.symbolRenderingMode(.hierarchical)
					} else if isSuggested {
						Text("Suggested")
							.font(.caption2.weight(.bold))
							.foregroundStyle(accent)
							.padding(.horizontal, 6)
							.padding(.vertical, 2)
							.background(accent.opacity(0.14), in: Capsule())
					}
				}

				Spacer(minLength: 8)

				Text(venue.name)
					.font(.subheadline.weight(.bold))
					.foregroundStyle(isSelected ? Color.white : titleColor)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
					.fixedSize(horizontal: false, vertical: true)

				if let label = venue.displayETALabel {
					Text(label)
						.font(.caption)
						.foregroundStyle(isSelected ? Color.white.opacity(0.9) : bodyColor)
						.padding(.top, 4)
						.lineLimit(1)
				}
			}
			.padding(14)
			.frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
			.background {
				RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
					.fill(isSelected ? AnyShapeStyle(accentGradient) : AnyShapeStyle(fieldBg))
					.overlay {
						RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
							.strokeBorder(
								isSelected ? Color.clear : Color.primary.opacity(0.06),
								lineWidth: 1
							)
					}
					.shadow(
						color: isSelected
							? accent.opacity(0.28)
							: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06),
						radius: isSelected ? 10 : 6,
						y: 3
					)
			}
		}
		.buttonStyle(.plain)
		.contextMenu {
			Button {
				onShowDetails?(venue)
			} label: {
				Label("Hours & details", systemImage: "clock")
			}
		}
		.accessibilityLabel(accessibilityLabel(for: venue, isSelected: isSelected, isSuggested: isSuggested))
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private func accessibilityLabel(for venue: GroundedVenue, isSelected: Bool, isSuggested: Bool) -> String {
		var parts = [venue.name]
		if isSuggested { parts.append("Suggested") }
		if isSelected { parts.append("Selected") }
		if let label = venue.displayETALabel { parts.append(label) }
		if let note = venue.suitabilityNote { parts.append(note) }
		return parts.joined(separator: ", ")
	}
}

/// Compact Pulse compose sheet — content-height (not a full-page card).
/// Matches mockup: header, draft, horizontal venue cards, actions.
struct PulseComposeSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(\.colorScheme) private var colorScheme

	let card: SuggestionCard
	@State private var selection: PulseComposeSelection
	@State private var contentHeight: CGFloat = 390
	@State private var detailMapItem: MKMapItem?
	var onSend: (SuggestionCard) -> Void
	var onCancel: () -> Void = {}

	private var draftMessage: String {
		PulseMessageComposer.draft(
			venue: hasVenues ? selection.selected : card.selectedVenue,
			hints: card.draftHints,
			reasonCodes: card.reasonCodes,
			sharedInterests: card.draftHints?.sharedInterests ?? []
		)
	}

	private var hasVenues: Bool {
		card.venueCandidates != nil
	}

	init(
		card: SuggestionCard,
		onSend: @escaping (SuggestionCard) -> Void,
		onCancel: @escaping () -> Void = {}
	) {
		self.card = card
		self.onSend = onSend
		self.onCancel = onCancel
		if let candidates = card.venueCandidates {
			_selection = State(initialValue: PulseComposeSelection(candidates: candidates))
		} else if let selected = card.selectedVenue {
			let candidates = GroundedVenueCandidates(suggested: selected, alternatives: [])
			_selection = State(initialValue: PulseComposeSelection(candidates: candidates))
		} else {
			let placeholder = GroundedVenue(
				name: card.venueName ?? "Nearby",
				coordinate: card.venueCoordinate ?? card.coordinate,
				distanceMeters: card.distanceMeters,
				displayETALabel: card.venueDisplayETALabel,
				queryType: .other
			)
			_selection = State(initialValue: PulseComposeSelection(
				candidates: GroundedVenueCandidates(suggested: placeholder)
			))
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			titleRow
				.padding(.horizontal, 20)
				.padding(.top, 28)

			Text("“\(draftMessage)”")
				.font(.body)
				.foregroundStyle(.secondary)
				.italic()
				.lineLimit(2)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.top, 12)
				.animation(.snappy(duration: 0.22), value: draftMessage)

			if hasVenues {
				Text("Meet at")
					.font(.caption.weight(.semibold))
					.tracking(0.8)
					.textCase(.uppercase)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 20)
					.padding(.top, 20)
					.padding(.bottom, 10)

				VenuePickerChipRow(selection: $selection) { venue in
					Task {
						detailMapItem = await VenueMapItemLoader.mapItem(for: venue)
					}
				}

				Button {
					Task {
						detailMapItem = await VenueMapItemLoader.mapItem(for: selection.selected)
					}
				} label: {
					Label("Hours & place details", systemImage: "clock")
						.font(.caption.weight(.semibold))
				}
				.buttonStyle(.plain)
				.foregroundStyle(.secondary)
				.padding(.horizontal, 20)
				.padding(.top, 8)
			}

			actionRow
				.padding(.horizontal, 20)
				.padding(.top, 20)
				.padding(.bottom, 12)
		}
		// Ideal height first, then lock the sheet detent to that — never expands to full screen.
		.fixedSize(horizontal: false, vertical: true)
		.background {
			GeometryReader { proxy in
				Color.clear
					.preference(key: PulseComposeHeightKey.self, value: proxy.size.height)
			}
		}
		.onPreferenceChange(PulseComposeHeightKey.self) { height in
			guard height > 0, abs(height - contentHeight) > 1 else { return }
			contentHeight = height
		}
		.presentationDetents([.height(contentHeight)])
		.presentationDragIndicator(.visible)
		.presentationCornerRadius(28)
		.mapItemDetailSheet(item: $detailMapItem, displaysMap: true)
	}

	private var titleRow: some View {
		HStack(alignment: .center, spacing: 12) {
			ZStack {
				Circle()
					.fill(
						LinearGradient(
							colors: [
								KismetTheme.Map.ring(for: card.availability),
								KismetTheme.Map.ring(for: card.availability).opacity(0.78)
							],
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						)
					)
					.frame(width: 44, height: 44)

				Image(systemName: "person.fill")
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white)
			}

			VStack(alignment: .leading, spacing: 3) {
				Text(card.displayName)
					.font(.title3.weight(.bold))

				Text(subtitleLine)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer(minLength: 0)
		}
	}

	private var subtitleLine: String {
		var parts: [String] = [card.formattedDistance]
		if hasVenues {
			parts.append(selection.selected.name)
		}
		return parts.joined(separator: " · ")
	}

	private var actionRow: some View {
		HStack(spacing: 12) {
			Button {
				onCancel()
				dismiss()
			} label: {
				Text("Not now")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(.primary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 15)
					.background(
						Capsule()
							.fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
							.shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 8, y: 3)
					)
			}
			.buttonStyle(.plain)

			Button {
				var outgoing = card
				outgoing.selectVenue(selection.lockedVenue())
				onSend(outgoing)
				dismiss()
			} label: {
				HStack(spacing: 7) {
					Image(systemName: "wave.3.right")
						.font(.subheadline.weight(.semibold))
					Text("Send Pulse")
						.font(.subheadline.weight(.semibold))
				}
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 15)
				.background(
					Capsule()
						.fill(
							LinearGradient(
								colors: [
									KismetTheme.Status.free,
									KismetTheme.Status.free.opacity(0.85)
								],
								startPoint: .topLeading,
								endPoint: .bottomTrailing
							)
						)
						.shadow(color: KismetTheme.Status.free.opacity(0.35), radius: 10, y: 4)
				)
			}
			.buttonStyle(.plain)
		}
	}
}

// MARK: - Preview host (sheet stays presented; Escape won’t leave a stale full-page canvas)

private struct PulseComposeHeightKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}

private struct PulseComposeSheetPreviewHost: View {
	@State private var isPresented = true
	var colorScheme: ColorScheme = .light

	var body: some View {
		Color.black.opacity(colorScheme == .dark ? 0.55 : 0.25)
			.ignoresSafeArea()
			.sheet(isPresented: $isPresented) {
				PulseComposeSheet(card: PulseComposePreviewData.card, onSend: { _ in })
					.preferredColorScheme(colorScheme)
			}
			.preferredColorScheme(colorScheme)
			.onChange(of: isPresented) { _, presented in
				// Keep the sheet up in canvas after Escape dismisses it.
				if !presented {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
						isPresented = true
					}
				}
			}
	}
}

// MARK: - Preview fixtures

enum PulseComposePreviewData {
	static let origin = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	static var candidates: GroundedVenueCandidates {
		let suggested = GroundedVenue(
			id: "v-suggested",
			name: "Third Wave Coffee",
			coordinate: CLLocationCoordinate2D(latitude: 12.9360, longitude: 77.6255),
			distanceMeters: 180,
			displayETAMinutes: 2,
			displayETALabel: "2 min walk",
			queryType: .coffee
		)
		let alts = [
			GroundedVenue(
				id: "v-alt-1",
				name: "Blue Tokai",
				coordinate: CLLocationCoordinate2D(latitude: 12.9375, longitude: 77.6260),
				distanceMeters: 420,
				displayETAMinutes: 5,
				displayETALabel: "5 min walk",
				queryType: .coffee
			),
			GroundedVenue(
				id: "v-alt-2",
				name: "Matteo Coffea",
				coordinate: CLLocationCoordinate2D(latitude: 12.9340, longitude: 77.6230),
				distanceMeters: 650,
				displayETAMinutes: 8,
				displayETALabel: "8 min walk",
				queryType: .coffee
			),
			GroundedVenue(
				id: "v-alt-3",
				name: "Café Coffee Day",
				coordinate: CLLocationCoordinate2D(latitude: 12.9388, longitude: 77.6280),
				distanceMeters: 900,
				displayETAMinutes: 11,
				displayETALabel: "11 min walk",
				queryType: .coffee
			)
		]
		return GroundedVenueCandidates(suggested: suggested, alternatives: alts)
	}

	static var card: SuggestionCard {
		let c = candidates
		return SuggestionCard(
			id: "ada",
			friendID: "ada",
			displayName: "Ada",
			coordinate: origin,
			availability: .free,
			presence: .available,
			distanceMeters: 220,
			reason: "Both free · Both like coffee",
			reasonCodes: [.bothFree, .sharedInterest, .nearbyWalk],
			factChips: ["Free right now", "3 min walk", "Both like coffee", "Nearby options available"],
			ctaTitle: "Send a Pulse",
			ctaSystemImage: "wave.3.right",
			venueName: c.suggested.name,
			venueETAMinutes: c.suggested.displayETAMinutes,
			confidence: 0.86,
			urgency: .now,
			isModelGenerated: true,
			pulseMessage: "Free to grab coffee at Third Wave Coffee?",
			venueCandidates: c,
			selectedVenue: c.suggested,
			venueResolution: .resolved(c),
			venueCoordinate: c.suggested.coordinate,
			venueDisplayETALabel: c.suggested.displayETALabel
		)
	}
}

#Preview("Compose sheet · light") {
	PulseComposeSheetPreviewHost(colorScheme: .light)
}

#Preview("Compose sheet · dark") {
	PulseComposeSheetPreviewHost(colorScheme: .dark)
}
