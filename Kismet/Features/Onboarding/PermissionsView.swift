import SwiftUI

struct PermissionsView: View {
	@Environment(\.colorScheme) private var colorScheme

	var onContinue: () -> Void = {}

	private let features = [
		KismetFeature(
			title: "Nearby Discovery",
			description: "See when friends are nearby.",
			symbol: "location.fill",
			color: .blue
		),
		KismetFeature(
			title: "Smart Availability",
			description: "Find the best time to meet.",
			symbol: "calendar",
			color: .red
		),
		KismetFeature(
			title: "Activity Insights",
			description: "Suggest plans based on your routine.",
			symbol: "figure.run",
			color: .green
		),
		KismetFeature(
			title: "Context Awareness",
			description: "Recommend moments that fit your day.",
			symbol: "brain.head.profile",
			color: .purple
		),
	]

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

						LazyVStack(spacing: 16) {
							ForEach(features) { feature in
								FeatureCard(feature: feature, foregroundColor: foregroundColor)
							}
						}
						.padding(.top, 24)
					}
					.padding(.horizontal, 32)
				}
				.scrollIndicators(.hidden)
				.safeAreaPadding(.top)
				.safeAreaInset(edge: .bottom, spacing: 0) {
					Button(action: onContinue) {
						Text("Continue")
							.font(.headline)
							.fontWeight(.bold)
							.textCase(.uppercase)
							.frame(maxWidth: .infinity)
							.frame(height: 54)
							.foregroundStyle(.white)
							.background(continueGradient, in: Capsule())
					}
					.buttonStyle(.plain)
					.accessibilityHint("Continues to Sign in with Apple")
					.padding(.horizontal, 32)
					.padding(.top, 8)
					.padding(.bottom, 24)
					.safeAreaPadding(.bottom, 8)
				}
			}
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("How Kismet\nConnects You")
				.font(.system(size: 36, weight: .bold, design: .rounded))
				.fontWidth(.expanded)
				.foregroundStyle(foregroundColor)

			Text("Bringing friends together at the right time and place.")
				.font(.body)
				.fontWeight(.regular)
				.foregroundStyle(foregroundColor.opacity(0.76))
				.fixedSize(horizontal: false, vertical: true)
		}
	}
}

private struct KismetFeature: Identifiable {
	let title: String
	let description: String
	let symbol: String
	let color: Color

	var id: String { title }
}

private struct FeatureCard: View {
	let feature: KismetFeature
	let foregroundColor: Color

	var body: some View {
		HStack(spacing: 18) {
			Image(systemName: feature.symbol)
				.font(.system(size: 27, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(feature.color)
				.frame(width: 44, height: 44)
				.background(feature.color.opacity(0.14), in: Circle())
				.accessibilityHidden(true)

			VStack(alignment: .leading, spacing: 4) {
				Text(feature.title)
					.font(.headline)
					.fontWeight(.semibold)
					.foregroundStyle(foregroundColor)

				Text(feature.description)
					.font(.subheadline)
					.foregroundStyle(foregroundColor.opacity(0.72))
					.fixedSize(horizontal: false, vertical: true)
			}

			Spacer(minLength: 0)
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
		.overlay {
			RoundedRectangle(cornerRadius: 20)
				.stroke(foregroundColor.opacity(0.14), lineWidth: 1)
		}
		.accessibilityElement(children: .combine)
	}
}

#Preview("Dark") {
	PermissionsView()
		.preferredColorScheme(.dark)
}

#Preview("Light") {
	PermissionsView()
		.preferredColorScheme(.light)
}
