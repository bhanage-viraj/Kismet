import SwiftUI

// MARK: - Design guesses
// Dark: CRT radar — near-black #0B0B0D, luminous green blooms ~0.40.
// Light: presence stage — cool gray #E8EBF0, graphite rings ~0.18,
// soft blue sweep/pulse. People carry color. Not a recolored CRT.
// Eyeball-adjust: bloom opacity, ring hairline, sweep fill.

extension KismetTheme {

	enum BumpScreen {
		case consent
		case nearby
	}

	/// Shared palette for Bump consent + Nearby radar surfaces.
	enum Bump {
		// Brand-stable accents
		static let violetStart = Color(red: 0.545, green: 0.361, blue: 0.965) // #8B5CF6
		static let violetEnd = Color(red: 0.655, green: 0.545, blue: 0.980) // #A78BFA
		static let accentGreen = Color(red: 0.12, green: 0.68, blue: 0.42)
		static let youDot = Color(red: 0.18, green: 0.45, blue: 0.98)

		static let available = Color(red: 0.12, green: 0.68, blue: 0.42)
		static let friendsOnly = Color(red: 0.55, green: 0.40, blue: 0.92)
		static let approximate = Color(red: 0.90, green: 0.58, blue: 0.12)
		static let eclipse = Color(red: 0.45, green: 0.48, blue: 0.50)

		static let buttonCornerRadius: CGFloat = 18
		static let cardCornerRadius: CGFloat = 20
		static let chromeButtonSize: CGFloat = 36
		static let consentAvatarSize: CGFloat = 88
		static let radarBlipAvatarSize: CGFloat = 52
		static let buttonHeight: CGFloat = 52
		static let radarHeightFraction: CGFloat = 0.55
		static let sweepConeDegrees: Double = 50
		static let ringRangesMeters: [CGFloat] = [100, 300, 500]
		static let maxRadarRangeMeters: CGFloat = 500

		static let acceptGradient = LinearGradient(
			colors: [violetStart, violetEnd],
			startPoint: .leading,
			endPoint: .trailing
		)

		// Dark — deep stage with luminous blooms
		private static let baseDark = Color(red: 0.043, green: 0.043, blue: 0.051) // #0B0B0D
		private static let secondaryFillDark = Color.white.opacity(0.10)
		private static let secondaryTextDark = Color.white.opacity(0.65)
		private static let headlineDark = Color.white
		private static let cardFillDark = Color.white.opacity(0.08)
		private static let blipBackingDark = Color.black.opacity(0.55)
		private static let chromeBorderDark = Color.clear
		private static let purpleGlowDark = Color(red: 0.45, green: 0.25, blue: 0.75).opacity(0.40)
		private static let greenGlowDark = Color(red: 0.10, green: 0.45, blue: 0.30).opacity(0.40)
		private static let greenGlowOuterDark = Color(red: 0.05, green: 0.30, blue: 0.22).opacity(0.22)
		private static let ringStrokeDark = Color(red: 0.30, green: 0.85, blue: 0.50).opacity(0.25)
		private static let sweepFillDark = Color(red: 0.20, green: 0.78, blue: 0.45).opacity(0.22)
		private static let pulseStrokeDark = Color(red: 0.30, green: 0.90, blue: 0.55).opacity(0.35)
		private static let tabPillDark = Color(red: 0.10, green: 0.35, blue: 0.22).opacity(0.85)
		private static let tabInactiveDark = Color.white.opacity(0.45)

		// Light — presence stage: cool gray canvas, slate ink, soft blue instrument
		private static let baseLight = Color(red: 0.910, green: 0.922, blue: 0.940) // #E8EBF0
		private static let secondaryFillLight = Color(red: 0.84, green: 0.87, blue: 0.91)
		private static let secondaryTextLight = Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.72)
		private static let headlineLight = Color(red: 0.08, green: 0.10, blue: 0.14) // deep slate
		private static let cardFillLight = Color.white.opacity(0.94)
		private static let blipBackingLight = Color.white.opacity(0.90)
		private static let chromeBorderLight = Color.black.opacity(0.12)
		private static let purpleGlowLight = Color(red: 0.58, green: 0.38, blue: 0.95).opacity(0.26)
		private static let nearbyGlowLight = Color(red: 0.38, green: 0.55, blue: 0.95).opacity(0.20)
		private static let nearbyGlowOuterLight = Color(red: 0.45, green: 0.60, blue: 0.92).opacity(0.10)
		private static let ringStrokeLight = Color.black.opacity(0.18)
		private static let sweepFillLight = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.22)
		private static let pulseStrokeLight = Color(red: 0.18, green: 0.42, blue: 0.92).opacity(0.38)
		private static let tabPillLight = Color(red: 0.82, green: 0.86, blue: 0.92)
		private static let tabInactiveLight = Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.48)

		static func base(for scheme: ColorScheme) -> Color {
			scheme == .dark ? baseDark : baseLight
		}

		static func headline(for scheme: ColorScheme) -> Color {
			scheme == .dark ? headlineDark : headlineLight
		}

		static func secondaryText(for scheme: ColorScheme) -> Color {
			scheme == .dark ? secondaryTextDark : secondaryTextLight
		}

		static func secondaryFill(for scheme: ColorScheme) -> Color {
			scheme == .dark ? secondaryFillDark : secondaryFillLight
		}

		static func chromeBorder(for scheme: ColorScheme) -> Color {
			scheme == .dark ? chromeBorderDark : chromeBorderLight
		}

		static func cardFill(for scheme: ColorScheme) -> Color {
			scheme == .dark ? cardFillDark : cardFillLight
		}

		static func blipBacking(for scheme: ColorScheme) -> Color {
			scheme == .dark ? blipBackingDark : blipBackingLight
		}

		static func ringStroke(for scheme: ColorScheme) -> Color {
			scheme == .dark ? ringStrokeDark : ringStrokeLight
		}

		static func sweepFill(for scheme: ColorScheme) -> Color {
			scheme == .dark ? sweepFillDark : sweepFillLight
		}

		static func pulseStroke(for scheme: ColorScheme) -> Color {
			scheme == .dark ? pulseStrokeDark : pulseStrokeLight
		}

		static func tabPill(for scheme: ColorScheme) -> Color {
			scheme == .dark ? tabPillDark : tabPillLight
		}

		static func tabInactive(for scheme: ColorScheme) -> Color {
			scheme == .dark ? tabInactiveDark : tabInactiveLight
		}

		static func youDot(for scheme: ColorScheme) -> Color {
			scheme == .dark
				? Color(red: 0.22, green: 0.48, blue: 1.00)
				: Color(red: 0.12, green: 0.42, blue: 0.95)
		}

		static func glowColor(for screen: BumpScreen, scheme: ColorScheme) -> Color {
			switch (screen, scheme) {
			case (.consent, .dark): purpleGlowDark
			case (.consent, _): purpleGlowLight
			case (.nearby, .dark): greenGlowDark
			case (.nearby, _): nearbyGlowLight
			}
		}

		static func outerGlowColor(for screen: BumpScreen, scheme: ColorScheme) -> Color {
			switch (screen, scheme) {
			case (.consent, .dark): purpleGlowDark.opacity(0.5)
			case (.consent, _): Color(red: 0.70, green: 0.55, blue: 0.98).opacity(0.14)
			case (.nearby, .dark): greenGlowOuterDark
			case (.nearby, _): nearbyGlowOuterLight
			}
		}

		static func background(for screen: BumpScreen, scheme: ColorScheme) -> some View {
			let glow = glowColor(for: screen, scheme: scheme)
			let outer = outerGlowColor(for: screen, scheme: scheme)
			let base = base(for: scheme)
			return ZStack {
				base

				if scheme == .light {
					lightAtmosphere(for: screen, base: base)
				}

				RadialGradient(
					colors: [glow, glow.opacity(scheme == .light ? 0.06 : 0.08), .clear],
					center: .center,
					startRadius: 12,
					endRadius: scheme == .light ? 340 : 420
				)

				RadialGradient(
					colors: [outer, .clear],
					center: UnitPoint(x: 0.5, y: 0.62),
					startRadius: 40,
					endRadius: scheme == .light ? 480 : 560
				)
			}
			.ignoresSafeArea()
		}

		@ViewBuilder
		private static func lightAtmosphere(for screen: BumpScreen, base: Color) -> some View {
			switch screen {
			case .nearby:
				LinearGradient(
					colors: [
						Color(red: 0.940, green: 0.948, blue: 0.965),
						base,
						Color(red: 0.870, green: 0.888, blue: 0.915),
					],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
			case .consent:
				LinearGradient(
					colors: [
						Color(red: 0.945, green: 0.940, blue: 0.970),
						base,
						Color(red: 0.880, green: 0.888, blue: 0.920),
					],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
			}
		}

		static func statusColor(for presence: RadarPresence) -> Color {
			switch presence {
			case .available: available
			case .friendsOnly: friendsOnly
			case .approximate: approximate
			case .eclipse: eclipse
			}
		}

		static func statusLabel(for presence: RadarPresence) -> String {
			switch presence {
			case .available: "Available"
			case .friendsOnly: "Friends only"
			case .approximate: "Approximate"
			case .eclipse: "Eclipse"
			}
		}
	}
}
