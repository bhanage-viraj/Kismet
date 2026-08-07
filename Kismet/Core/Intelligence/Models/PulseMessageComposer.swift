import Foundation

enum PulseTimeOfDay: String, Sendable, Hashable {
	case morning
	case midday
	case afternoon
	case evening
	case night

	static func from(date: Date, calendar: Calendar = .current) -> PulseTimeOfDay {
		let hour = calendar.component(.hour, from: date)
		switch hour {
		case 5..<11: return .morning
		case 11..<14: return .midday
		case 14..<17: return .afternoon
		case 17..<21: return .evening
		default: return .night
		}
	}
}

/// Compact context snapshot so venue switches can rewrite the draft without regenerating Intelligence.
struct PulseDraftHints: Sendable, Hashable {
	var sharedInterests: [String]
	var reasonCodes: [ExplainCode]
	var pastMeetupCount: Int
	var preferredCategory: VenueCategory?
	var timeOfDay: PulseTimeOfDay
	var motion: MotionActivityKind
	var freeUntil: Date?
	var friendFreeUntil: Date?
	var weather: WeatherConditionKind
	var isUsualMeetupTime: Bool

	static func make(
		item: RankedOpportunity,
		context: KismetContext
	) -> PulseDraftHints {
		let stats = item.learnedStats
		return PulseDraftHints(
			sharedInterests: item.friend.sharedInterests,
			reasonCodes: item.reasonCodes,
			pastMeetupCount: stats?.completedCount ?? 0,
			preferredCategory: stats?.preferredCategories.first,
			timeOfDay: .from(date: context.generatedAt),
			motion: context.motion.activity,
			freeUntil: context.calendar.freeUntil ?? context.user.freeUntil,
			friendFreeUntil: item.friend.freeUntil,
			weather: context.weather.condition,
			isUsualMeetupTime: item.reasonCodes.contains(.usualMeetupTime)
		)
	}
}

/// Deterministic, context-aware Pulse body.
/// Uses venue + interests + meetup memory + time + weather + motion + calendar.
enum PulseMessageComposer {
	static func draft(
		venue: GroundedVenue?,
		hints: PulseDraftHints? = nil,
		reasonCodes: [ExplainCode] = [],
		sharedInterests: [String] = []
	) -> String {
		let hints = hints ?? PulseDraftHints(
			sharedInterests: sharedInterests,
			reasonCodes: reasonCodes,
			pastMeetupCount: 0,
			preferredCategory: nil,
			timeOfDay: .from(date: Date()),
			motion: .unknown,
			freeUntil: nil,
			friendFreeUntil: nil,
			weather: .unknown,
			isUsualMeetupTime: reasonCodes.contains(.usualMeetupTime)
		)

		let type = resolvedType(venue: venue, hints: hints)
		let name = normalizedName(venue?.name)
		var sentence = compose(type: type, name: name, hints: hints)

		if let window = freeWindowSuffix(hints: hints) {
			sentence = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "?"))
			sentence += " \(window)?"
		} else if !sentence.hasSuffix("?") {
			sentence += "?"
		}

		return sentence
	}

	static func draft(updatingFrom previous: String?, venue: GroundedVenue, hints: PulseDraftHints?) -> String {
		draft(venue: venue, hints: hints)
	}

	// MARK: - Compose

	private static func compose(
		type: VenueQueryType,
		name: String?,
		hints: PulseDraftHints
	) -> String {
		// 1) Habit / past meetups
		if hints.pastMeetupCount > 0, typeMatchesPreferred(type, preferred: hints.preferredCategory) {
			switch type {
			case .coffee, .cafe:
				return name.map { "Coffee at \($0) again" } ?? "Coffee again"
			case .restaurant:
				return name.map { "Food at \($0) again" } ?? "Food again"
			case .park:
				return name.map { "Walk at \($0) again" } ?? "Walk again"
			case .other:
				return name.map { "Hang at \($0) again" } ?? "Hang again"
			}
		}

		// 2) Usual meetup hour
		if hints.isUsualMeetupTime {
			return "Our usual time — \(activityCore(type: type, name: name, hints: hints))"
		}

		// 3) Weather
		switch hints.weather {
		case .rain, .snow:
			switch type {
			case .park:
				return "It's wet out — grab something warm indoors"
			case .coffee, .cafe:
				return name.map { "Rainy out — coffee at \($0)" } ?? "Rainy out — coffee indoors"
			case .restaurant:
				return name.map { "Wet weather — bite at \($0)" } ?? "Wet weather — grab a bite indoors"
			case .other:
				return name.map { "Staying dry at \($0)" } ?? "Staying dry — hang indoors"
			}
		case .clear where type == .park:
			return name.map { "Nice out — walk at \($0)" } ?? "Nice out — free for a walk"
		case .hot where type == .coffee || type == .cafe:
			return name.map { "Hot day — iced coffee at \($0)" } ?? "Hot day — iced coffee"
		default:
			break
		}

		// 4) Shared interest
		if let interest = hints.sharedInterests.first,
		   VenueQueryType.infer(fromPlaceTypeSignal: interest) != nil {
			return "Both into \(interest.lowercased()) — \(activityCore(type: type, name: name, hints: hints))"
		}

		// 5) Motion
		if hints.motion == .walking {
			return "Since we're both nearby — \(activityCore(type: type, name: name, hints: hints))"
		}

		// 6) Time of day framing
		let core = activityCore(type: type, name: name, hints: hints)
		switch hints.timeOfDay {
		case .morning:
			return "Morning — \(core)"
		case .midday:
			return core.capitalizedFirst
		case .afternoon:
			return "Afternoon free — \(core)"
		case .evening:
			return "Evening — \(core)"
		case .night:
			return "Tonight — \(core)"
		}
	}

	private static func activityCore(
		type: VenueQueryType,
		name: String?,
		hints: PulseDraftHints
	) -> String {
		switch type {
		case .coffee, .cafe:
			return name.map { "free to grab coffee at \($0)" } ?? "free to grab coffee"
		case .restaurant:
			switch hints.timeOfDay {
			case .midday:
				return name.map { "free for lunch at \($0)" } ?? "free for lunch"
			case .evening, .night:
				return name.map { "free for dinner at \($0)" } ?? "free for dinner"
			default:
				return name.map { "free to grab a bite at \($0)" } ?? "free to grab a bite"
			}
		case .park:
			return name.map { "free for a walk at \($0)" } ?? "free for a walk"
		case .other:
			return name.map { "free to meet at \($0)" } ?? "free to hang"
		}
	}

	private static func freeWindowSuffix(hints: PulseDraftHints) -> String? {
		let until = hints.friendFreeUntil ?? hints.freeUntil
		guard let until, until > Date() else { return nil }
		let minutes = until.timeIntervalSinceNow / 60
		guard minutes > 15, minutes < 4 * 60 else { return nil }
		let time = until.formatted(date: .omitted, time: .shortened)
		return "before \(time)"
	}

	private static func resolvedType(venue: GroundedVenue?, hints: PulseDraftHints) -> VenueQueryType {
		if let type = venue?.queryType, type != .other { return type }
		if let preferred = hints.preferredCategory, let mapped = VenueQueryType.from(venueCategory: preferred) {
			return mapped
		}
		if hints.reasonCodes.contains(.goodTimeForCoffee) { return .coffee }
		if let fromInterest = hints.sharedInterests.lazy.compactMap({ VenueQueryType.infer(fromPlaceTypeSignal: $0) }).first {
			return fromInterest
		}
		if hints.weather == .clear || hints.weather == .hot { return .park }
		if hints.weather == .rain || hints.weather == .snow || hints.weather == .cold { return .coffee }
		return venue?.queryType ?? .other
	}

	private static func typeMatchesPreferred(_ type: VenueQueryType, preferred: VenueCategory?) -> Bool {
		guard let preferred else { return false }
		switch (type, preferred) {
		case (.coffee, .coffee), (.cafe, .coffee), (.restaurant, .food), (.park, .walk):
			return true
		default:
			return false
		}
	}

	private static func normalizedName(_ raw: String?) -> String? {
		guard let raw else { return nil }
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

private extension String {
	var capitalizedFirst: String {
		guard let first else { return self }
		return String(first).uppercased() + dropFirst()
	}
}
