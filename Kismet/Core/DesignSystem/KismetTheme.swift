import SwiftUI

enum KismetTheme {
	enum Status {
		static let free = Color(red: 0.20, green: 0.78, blue: 0.35)
		static let busy = Color(red: 1.00, green: 0.58, blue: 0.00)
		static let unknown = Color(red: 0.69, green: 0.32, blue: 0.87)
		static let away = Color(red: 1.00, green: 0.27, blue: 0.23)
	}

	enum Map {
		static let userPulse = Color(red: 0.20, green: 0.48, blue: 1.00)
		static let youPin = Color(red: 0.90, green: 0.22, blue: 0.21)
		static let ringStroke = Color.primary.opacity(0.12)
		static let annotationLabelFill = Color(.systemBackground)
		static let headerForeground = Color.primary
		static let secondaryLabel = Color.secondary

		static func glow(for availability: MapAvailability) -> Color {
			switch availability {
			case .free: Status.free.opacity(0.35)
			case .busy: Status.busy.opacity(0.35)
			case .unknown: Status.unknown.opacity(0.35)
			}
		}

		static func ring(for availability: MapAvailability) -> Color {
			switch availability {
			case .free: Status.free
			case .busy: Status.busy
			case .unknown: Status.unknown
			}
		}
	}

	enum Insight {
		static let sheetBackgroundLight = Color(red: 0.973, green: 0.965, blue: 0.945) // #F8F6F1
		static let sheetBackgroundDark = Color(red: 0.14, green: 0.14, blue: 0.15)
		static let cardBackgroundLight = Color.white
		static let cardBackgroundDark = Color(red: 0.18, green: 0.18, blue: 0.19)
		static let titleColorLight = Color(red: 0.22, green: 0.24, blue: 0.27)
		static let titleColorDark = Color(red: 0.92, green: 0.92, blue: 0.93)
		static let bodyColorLight = Color(red: 0.42, green: 0.45, blue: 0.48)
		static let bodyColorDark = Color(red: 0.72, green: 0.73, blue: 0.75)
		static let freeCTABackground = Color(red: 0.88, green: 0.96, blue: 0.90)
		static let freeCTAForeground = Color(red: 0.10, green: 0.52, blue: 0.34)
		static let busyCTABackground = Color(red: 0.98, green: 0.92, blue: 0.84)
		static let busyCTAForeground = Color(red: 0.62, green: 0.38, blue: 0.12)
		static let unknownCTABackground = Color(red: 0.94, green: 0.90, blue: 0.98)
		static let unknownCTAForeground = Color(red: 0.48, green: 0.24, blue: 0.68)
		static let cardCornerRadius: CGFloat = 20
		static let sheetCornerRadius: CGFloat = 30
		static let buttonCornerRadius: CGFloat = 14
		static let grabberWidth: CGFloat = 40
		static let cardAvatarSize: CGFloat = 36

		static func sheetBackground(for scheme: ColorScheme) -> Color {
			scheme == .dark ? sheetBackgroundDark : sheetBackgroundLight
		}

		static func cardBackground(for scheme: ColorScheme) -> Color {
			scheme == .dark ? cardBackgroundDark : cardBackgroundLight
		}

		static func titleColor(for scheme: ColorScheme) -> Color {
			scheme == .dark ? titleColorDark : titleColorLight
		}

		static func bodyColor(for scheme: ColorScheme) -> Color {
			scheme == .dark ? bodyColorDark : bodyColorLight
		}

		static func ctaBackground(for availability: MapAvailability) -> Color {
			switch availability {
			case .free: freeCTABackground
			case .busy: busyCTABackground
			case .unknown: unknownCTABackground
			}
		}

		static func ctaForeground(for availability: MapAvailability) -> Color {
			switch availability {
			case .free: freeCTAForeground
			case .busy: busyCTAForeground
			case .unknown: unknownCTAForeground
			}
		}
	}

	enum Chrome {
		static let avatarSize: CGFloat = 40
		static let annotationAvatarSize: CGFloat = 52
		static let detailAvatarSize: CGFloat = 88
		static let statusDotSize: CGFloat = 10
		static let headerCornerRadius: CGFloat = 24
	}
}
