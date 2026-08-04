import SwiftUI

/// Compact presence control for the map header. Collapsed = selected state chip;
/// expanded = a slim menu with icon + title that slides down over the map.
struct PresenceModePicker: View {
	@Binding var selection: PresenceState
	@Binding var isExpanded: Bool
	var buttonSize: CGFloat = KismetTheme.Chrome.avatarSize
	/// Fired when the user picks Friends Only so the host can present the subset sheet.
	var onSelectFriendsOnly: (() -> Void)? = nil

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	private var optionSize: CGFloat { 28 }

	private var animation: Animation {
		reduceMotion
			? .easeInOut(duration: 0.15)
			: .spring(response: 0.32, dampingFraction: 0.84)
	}

	private var otherStates: [PresenceState] {
		PresenceState.allCases.filter { $0 != selection }
	}

	var body: some View {
		VStack(alignment: .trailing, spacing: isExpanded ? 2 : 0) {
			if isExpanded {
				optionRow(for: selection, isSelected: true) {
					withAnimation(animation) {
						isExpanded = false
					}
					if selection == .friendsOnly {
						onSelectFriendsOnly?()
					}
				}
				.accessibilityLabel("Presence, \(selection.title), selected")
				.accessibilityHint(
					selection == .friendsOnly
						? "Collapses options. Double tap again from the menu to edit who can see you."
						: "Collapses options"
				)

				ForEach(otherStates, id: \.self) { state in
					optionRow(for: state, isSelected: false) {
						UIImpactFeedbackGenerator(style: .light).impactOccurred()
						withAnimation(animation) {
							selection = state
							isExpanded = false
						}
						if state == .friendsOnly {
							onSelectFriendsOnly?()
						}
					}
					.transition(
						reduceMotion
							? .opacity
							: .move(edge: .top).combined(with: .opacity)
					)
				}
			} else {
				fab(for: selection) {
					withAnimation(animation) {
						isExpanded = true
					}
				}
				.accessibilityLabel("Presence, \(selection.title)")
				.accessibilityHint("Shows presence options")
			}
		}
		.padding(.vertical, isExpanded ? 6 : 0)
		.padding(.leading, isExpanded ? 10 : 0)
		.padding(.trailing, isExpanded ? 5 : 0)
		.background {
			if isExpanded {
				RoundedRectangle(cornerRadius: buttonSize / 2 + 5, style: .continuous)
					.fill(.ultraThinMaterial)
					.shadow(color: .black.opacity(0.12), radius: 10, y: 4)
					.transition(.opacity)
			}
		}
		.accessibilityElement(children: .contain)
	}

	private func optionRow(
		for state: PresenceState,
		isSelected: Bool,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			HStack(spacing: 8) {
				Text(state.title)
					.font(.caption.weight(isSelected ? .bold : .semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)

				iconCircle(for: state, size: isSelected ? buttonSize : optionSize, emphasized: isSelected)
			}
			.padding(.vertical, 4)
			.padding(.leading, 4)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(state.title)
		.accessibilityHint(state.subtitle)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
	}

	private func fab(for state: PresenceState, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			ZStack(alignment: .bottomTrailing) {
				iconCircle(for: state, size: buttonSize, emphasized: true)

				Image(systemName: "chevron.down")
					.font(.system(size: 7, weight: .bold))
					.foregroundStyle(.white)
					.padding(3.5)
					.background(state.statusColor.gradient, in: Circle())
					.overlay {
						Circle().stroke(.white.opacity(0.85), lineWidth: 1.5)
					}
					.offset(x: 1, y: 1)
			}
		}
		.buttonStyle(.plain)
	}

	private func iconCircle(for state: PresenceState, size: CGFloat, emphasized: Bool) -> some View {
		ZStack {
			Circle()
				.fill(state.statusColor.opacity(emphasized ? 0.20 : 0.12))

			Image(systemName: state.systemImage)
				.font(.system(size: size * 0.42, weight: .semibold))
				.foregroundStyle(state.statusColor)
				.symbolRenderingMode(.hierarchical)
		}
		.frame(width: size, height: size)
		.overlay {
			Circle()
				.stroke(
					emphasized ? state.statusColor.opacity(0.5) : Color.clear,
					lineWidth: 1.5
				)
		}
	}
}

#if DEBUG
#Preview("Collapsed") {
	HStack {
		Spacer()
		PresenceModePicker(
			selection: .constant(.available),
			isExpanded: .constant(false)
		)
	}
	.padding()
	.background(.ultraThinMaterial)
}

#Preview("Expanded · Dark") {
	PresenceModePickerPreview()
		.preferredColorScheme(.dark)
}

private struct PresenceModePickerPreview: View {
	@State private var selection: PresenceState = .friendsOnly
	@State private var isExpanded = true

	var body: some View {
		ZStack(alignment: .top) {
			Color(red: 0.12, green: 0.14, blue: 0.18).ignoresSafeArea()

			HStack {
				Text("You")
				Spacer()
			}
			.padding()
			.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
			.overlay(alignment: .topTrailing) {
				PresenceModePicker(selection: $selection, isExpanded: $isExpanded)
					.padding(.top, 10)
					.padding(.trailing, 14)
			}
			.padding()
		}
	}
}
#endif
