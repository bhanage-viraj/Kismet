import SwiftUI
import WidgetKit

/// Green rounded-square SF Symbol chip used by meetup Live Activity + rows.
/// Symbol is passed in — works for coffee, lunch, walk, calendar, etc.
struct MeetupIconChip: View {
	enum Style {
		/// Soft tint — home-screen widgets / meetup rows.
		case soft
		/// Solid green fill + white glyph — Live Activity header (matches mockup).
		case solid
	}

	@Environment(\.widgetRenderingMode) private var renderingMode

	var systemImage: String
	var size: CGFloat = 36
	var cornerRadius: CGFloat = 10
	var symbolFont: Font = .body.weight(.semibold)
	var style: Style = .soft

	var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
				.fill(fillColor)
				.frame(width: size, height: size)
				// Solid chips: fill joins the accent group (system tint). Soft chips keep fill in the default group.
				.widgetAccentable(style == .solid)
			Image(systemName: systemImage)
				.font(symbolFont)
				.foregroundStyle(glyphColor)
				// Soft chips: glyph is the accent. Solid chips: white glyph stays in the default group.
				.widgetAccentable(style == .soft)
		}
		.accessibilityHidden(true)
	}

	private var fillColor: Color {
		switch style {
		case .soft:
			renderingMode.isAccented
				? PresenceStatusColor.softChipFill(for: renderingMode)
				: PresenceStatusColor.free.opacity(0.18)
		case .solid:
			PresenceStatusColor.free
		}
	}

	private var glyphColor: Color {
		switch style {
		case .soft: PresenceStatusColor.free
		case .solid: .white
		}
	}
}
