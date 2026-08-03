import SwiftUI
import WidgetKit

/// Static illustrative map for Extra Large — parks, streets, water. No MapKit.
struct StylizedMapBackground: View {
	@Environment(\.colorScheme) private var colorScheme

	private var land: Color {
		colorScheme == .dark
			? Color(red: 0.14, green: 0.16, blue: 0.15)
			: Color(red: 0.90, green: 0.93, blue: 0.88)
	}

	private var park: Color {
		colorScheme == .dark
			? Color(red: 0.18, green: 0.28, blue: 0.22)
			: Color(red: 0.72, green: 0.86, blue: 0.74)
	}

	private var street: Color {
		colorScheme == .dark
			? Color(red: 0.22, green: 0.22, blue: 0.24)
			: Color(red: 0.96, green: 0.96, blue: 0.95)
	}

	private var water: Color {
		colorScheme == .dark
			? Color(red: 0.16, green: 0.24, blue: 0.32)
			: Color(red: 0.72, green: 0.84, blue: 0.92)
	}

	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height

			ZStack {
				land

				// Parks
				RoundedRectangle(cornerRadius: 18, style: .continuous)
					.fill(park)
					.frame(width: w * 0.42, height: h * 0.28)
					.position(x: w * 0.28, y: h * 0.32)

				RoundedRectangle(cornerRadius: 22, style: .continuous)
					.fill(park.opacity(0.85))
					.frame(width: w * 0.36, height: h * 0.22)
					.position(x: w * 0.78, y: h * 0.55)

				// Water
				Capsule()
					.fill(water)
					.frame(width: w * 0.55, height: h * 0.12)
					.rotationEffect(.degrees(-12))
					.position(x: w * 0.62, y: h * 0.22)

				// Streets
				streetPath(width: w, height: h)
			}
		}
		.clipped()
	}

	private func streetPath(width w: CGFloat, height h: CGFloat) -> some View {
		ZStack {
			Capsule()
				.fill(street)
				.frame(width: w * 1.2, height: 14)
				.rotationEffect(.degrees(18))
				.position(x: w * 0.5, y: h * 0.48)

			Capsule()
				.fill(street)
				.frame(width: w * 1.1, height: 12)
				.rotationEffect(.degrees(-28))
				.position(x: w * 0.45, y: h * 0.68)

			Capsule()
				.fill(street.opacity(0.9))
				.frame(width: 12, height: h * 0.9)
				.position(x: w * 0.38, y: h * 0.5)

			Capsule()
				.fill(street.opacity(0.85))
				.frame(width: 10, height: h * 0.7)
				.position(x: w * 0.72, y: h * 0.42)
		}
	}
}

/// Avatar in a teardrop map pin.
struct MapFriendPin: View {
	let card: WidgetAppGroup.Card
	var size: CGFloat = 36

	private var statusColor: Color { PresenceStatusColor.status(card.status) }

	var body: some View {
		VStack(spacing: 0) {
			ZStack {
				Circle()
					.fill(statusColor)
					.frame(width: size + 6, height: size + 6)

				PresenceAvatar(
					card: card,
					size: size,
					ringWidth: 2,
					ringGap: 1.5,
					ringTrackColor: Color(.systemBackground),
					showsStatusDot: false
				)
			}

			// Teardrop tip
			Triangle()
				.fill(statusColor)
				.frame(width: 12, height: 10)
				.offset(y: -2)
		}
		.shadow(color: .black.opacity(0.18), radius: 3, y: 2)
		.widgetAccentable()
	}
}

/// Simple downward triangle for the pin tip.
private struct Triangle: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
		path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
		path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
		path.closeSubpath()
		return path
	}
}

/// Blue “you are here” marker with concentric rings.
struct MapYouMarker: View {
	var body: some View {
		ZStack {
			Circle()
				.stroke(PresenceStatusColor.you.opacity(0.25), lineWidth: 2)
				.frame(width: 42, height: 42)
			Circle()
				.stroke(PresenceStatusColor.you.opacity(0.45), lineWidth: 2)
				.frame(width: 28, height: 28)
			Circle()
				.fill(PresenceStatusColor.you)
				.frame(width: 12, height: 12)
				.overlay {
					Circle()
						.strokeBorder(Color.white, lineWidth: 2)
				}
		}
		.widgetAccentable()
		.accessibilityLabel("Your location")
	}
}
