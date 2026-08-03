import SwiftUI
import UIKit
import WidgetKit

/// Single source of truth for presence accents and widget surfaces.
/// Views must not hardcode hex — go through this type.
///
/// Tinted / clear Home Screen (iOS 18+) uses `WidgetRenderingMode.accented`.
/// Soft fills and photo rendering adapt so the same layouts stay legible while
/// status accents pick up the system tint via `.widgetAccentable()`.
/// See: Optimizing your widget for accented rendering mode and Liquid Glass.
enum PresenceStatusColor {
	// MARK: - Status accents

	/// Free / available — Apple system mint (Find My–adjacent), brighter on dark OLED.
	static let free = Color(
		light: Color(red: 0.204, green: 0.780, blue: 0.349), // systemGreen #34C759
		dark: Color(red: 0.188, green: 0.820, blue: 0.345) // #30D158
	)

	/// Busy / working nearby.
	static let busy = Color(red: 1.0, green: 0.624, blue: 0.110) // #FF9F1C

	/// Approximate / nearby (non-free) muted status.
	static let nearby = Color(red: 0.55, green: 0.55, blue: 0.58)

	/// Current user / "you" location marker.
	static let you = Color(red: 0.243, green: 0.557, blue: 0.969) // #3E8EF7

	// MARK: - Surfaces

	/// Outer widget canvas behind the card.
	static let canvas = Color(
		light: Color(red: 0.949, green: 0.945, blue: 0.933), // #F2F1EE
		dark: Color(red: 0.043, green: 0.043, blue: 0.051) // #0B0B0D
	)

	/// Primary card fill inside `containerBackground`.
	static let card = Color(
		light: Color(red: 0.969, green: 0.965, blue: 0.953), // #F7F6F3
		dark: Color(red: 0.063, green: 0.063, blue: 0.071) // #101012
	)

	/// Elevated inner chips / meetup rows.
	static let elevatedCard = Color(
		light: Color.white,
		dark: Color(red: 0.090, green: 0.090, blue: 0.102) // #17171A
	)

	static let subtleFill = Color.primary.opacity(0.04)
	static let cardFill = Color.primary.opacity(0.06)

	// MARK: - Text

	static let title = Color.primary
	static let secondary = Color.secondary
	static let tertiary = Color.secondary.opacity(0.7)

	// MARK: - Accented / tinted Home Screen

	/// Soft chip / icon disc behind an accentable glyph.
	/// Full color keeps the brand mint wash; accented uses a white silhouette
	/// so the tinted glyph stays readable on Liquid Glass.
	static func softChipFill(for mode: WidgetRenderingMode) -> Color {
		mode.isAccented ? Color.primary.opacity(0.16) : free.opacity(0.14)
	}

	/// Elevated meetup / footer card fill.
	static func elevatedFill(for mode: WidgetRenderingMode) -> Color {
		mode.isAccented ? Color.primary.opacity(0.14) : cardFill
	}

	/// Overlay pill on map widgets.
	static func mapOverlayFill(for mode: WidgetRenderingMode) -> Color {
		mode.isAccented ? Color.primary.opacity(0.18) : Color.clear
	}

	// MARK: - Mapping

	static func status(_ status: WidgetAppGroup.WidgetStatus) -> Color {
		switch status {
		case .free: free
		case .busy: busy
		case .nearby: nearby
		}
	}

	static func avatarGradient(for name: String) -> [Color] {
		avatarGradient(for: name, mode: .fullColor)
	}

	/// Monogram disc — colorful in full color, luminance-only when tinted.
	static func avatarGradient(for name: String, mode: WidgetRenderingMode) -> [Color] {
		if mode.isAccented {
			return [Color.primary.opacity(0.38), Color.primary.opacity(0.18)]
		}
		let palette: [[Color]] = [
			[Color(red: 0.95, green: 0.75, blue: 0.55), Color(red: 0.85, green: 0.45, blue: 0.35)],
			[Color(red: 0.55, green: 0.70, blue: 0.95), Color(red: 0.35, green: 0.45, blue: 0.85)],
			[Color(red: 0.70, green: 0.85, blue: 0.55), Color(red: 0.35, green: 0.65, blue: 0.45)],
			[Color(red: 0.90, green: 0.60, blue: 0.75), Color(red: 0.70, green: 0.35, blue: 0.55)],
		]
		let index = abs(name.hashValue) % palette.count
		return palette[index]
	}
}

extension WidgetRenderingMode {
	/// Home Screen tinted / clear appearance, or watch accent faces.
	var isAccented: Bool { self == .accented }
}

// MARK: - Adaptive color helper

private extension Color {
	init(light: Color, dark: Color) {
		self.init(uiColor: UIColor { traits in
			traits.userInterfaceStyle == .dark
				? UIColor(dark)
				: UIColor(light)
		})
	}
}
