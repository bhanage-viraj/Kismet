import SwiftUI

struct InterestsView: View {
	@Environment(\.colorScheme) private var colorScheme
	@State private var selectedInterests: Set<String> = []

	var onContinue: ([String]) -> Void = { _ in }

	private var allInterests: [InterestItem] {
		InterestCatalog.all
	}

	private var foregroundColor: Color {
		colorScheme == .dark
			? Color(red: 0.95, green: 0.95, blue: 0.95)
			: Color(red: 0.05, green: 0.10, blue: 0.13)
	}

	private var continueGradient: LinearGradient {
		LinearGradient(
			colors: [
				Color(red: 0.96, green: 0.45, blue: 0.28),
				Color(red: 0.88, green: 0.31, blue: 0.24),
			],
			startPoint: .leading,
			endPoint: .trailing
		)
	}

	var body: some View {
		GeometryReader { geometry in
			ZStack {
				Image(colorScheme == .dark ? "blacksecond" : "whitesecond")
					.resizable()
					.scaledToFill()
					.frame(width: geometry.size.width, height: geometry.size.height)
					.scaleEffect(1.05)
					.blur(radius: 9)
					.clipped()
					.ignoresSafeArea()
					.accessibilityHidden(true)

				Color.black
					.opacity(colorScheme == .dark ? 0.20 : 0.03)
					.ignoresSafeArea()

				ScrollView {
					VStack(alignment: .leading, spacing: 0) {
						header
							.padding(.top, 64)

						LazyVGrid(
							columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
							spacing: 10
						) {
							ForEach(allInterests) { interest in
								interestButton(interest)
							}
						}
						.padding(.top, 24)

						Button {
							onContinue(selectedInterests.sorted())
						} label: {
							Text("Continue")
								.font(.headline)
								.fontWeight(.bold)
								.frame(maxWidth: .infinity)
								.frame(height: 54)
								.foregroundStyle(.white)
								.background(continueGradient, in: Capsule())
						}
						.buttonStyle(.plain)
						.disabled(selectedInterests.isEmpty)
						.opacity(selectedInterests.isEmpty ? 0.45 : 1)
						.accessibilityHint("Continues with your selected interests")
						.padding(.top, 24)
					}
					.padding(.horizontal, 32)
				}
				.scrollIndicators(.hidden)
				.safeAreaPadding(.top)
			}
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("What are you into?")
				.font(.system(size: 36, weight: .bold, design: .rounded))
				.fontWidth(.expanded)
				.foregroundStyle(foregroundColor)

			Text("Pick a few interests to help us find your people.")
				.font(.body)
				.foregroundStyle(foregroundColor.opacity(0.76))
		}
	}

	private func interestButton(_ interest: InterestItem) -> some View {
		let isSelected = selectedInterests.contains(interest.id)

		return Button {
			withAnimation(.easeInOut(duration: 0.18)) {
				if isSelected {
					selectedInterests.remove(interest.id)
				} else {
					selectedInterests.insert(interest.id)
				}
			}
		} label: {
			VStack(spacing: 10) {
				Image(systemName: interest.symbol)
					.font(.system(size: 27, weight: .semibold))
					.symbolRenderingMode(.hierarchical)
					.foregroundStyle(interest.color)
					.frame(height: 32)

				Text(interest.name)
					.font(.subheadline)
					.fontWeight(.semibold)
					.foregroundStyle(foregroundColor)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
			}
			.frame(maxWidth: .infinity)
			.frame(height: 94)
			.background(
				isSelected ? interest.color.opacity(0.18) : Color.clear,
				in: RoundedRectangle(cornerRadius: 18)
			)
			.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
			.overlay {
				RoundedRectangle(cornerRadius: 18)
					.stroke(
						isSelected ? interest.color : foregroundColor.opacity(0.12),
						lineWidth: isSelected ? 2 : 1
					)
			}
			.overlay(alignment: .topTrailing) {
				if isSelected {
					Image(systemName: "checkmark.circle.fill")
						.font(.caption)
						.foregroundStyle(interest.color)
						.padding(8)
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(interest.name)
		.accessibilityValue(isSelected ? "Selected" : "Not selected")
	}
}

#Preview("Dark") {
	InterestsView()
		.preferredColorScheme(.dark)
}

#Preview("Light") {
	InterestsView()
		.preferredColorScheme(.light)
}
