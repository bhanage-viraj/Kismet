import EventKit
import SwiftUI

struct AvailabilitySetupView: View {
	@Environment(\.colorScheme) private var colorScheme
	@State private var weekdayAvailability = "Choose"
	@State private var weekendAvailability = "Choose"
	@State private var dailyWindows = AvailabilityDay.defaults
	@State private var isShowingCustomHours = false
	@State private var isRequestingCalendarPermission = false
	@State private var isCalendarStepComplete =
		EKEventStore.authorizationStatus(for: .event) != .notDetermined

	var isSaving = false
	var onFinish: (AvailabilitySetupRequestDTO) -> Void = { _ in }

	private let weekdayOptions = ["After 5:00 PM", "After 6:00 PM", "After 7:00 PM", "Anytime"]
	private let weekendOptions = ["Anytime", "Mornings", "Afternoons", "Evenings"]
	private let eventStore = EKEventStore()

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

				if isCalendarStepComplete {
					availabilityContent
						.transition(.opacity)
				} else {
					calendarPermissionIntro
						.transition(.opacity)
				}
			}
		}
		.sheet(isPresented: $isShowingCustomHours) {
			customHoursSheet
		}
		.task {
			if isCalendarStepComplete {
				await refreshBusyFromCalendar()
			}
		}
	}

	private var availabilityContent: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				header
					.padding(.top, 64)

				VStack(spacing: 10) {
					availabilityMenu(
						title: "Weekdays",
						value: weekdayAvailability,
						options: weekdayOptions,
						onSelect: applyWeekdayPreset
					)

					availabilityMenu(
						title: "Weekends",
						value: weekendAvailability,
						options: weekendOptions,
						onSelect: applyWeekendPreset
					)

					Button {
						isShowingCustomHours = true
					} label: {
						availabilityRow(
							title: "Custom",
							value: "Set each day’s hours",
							showsDetailBelow: true
						)
					}
					.buttonStyle(.plain)
				}
				.padding(.top, 28)

				WeekAvailabilityChart(
					dailyWindows: dailyWindows,
					foregroundColor: foregroundColor
				)
				.padding(.top, 26)

				legend
					.padding(.top, 14)

				Button {
					Task {
						await saveAvailability()
					}
				} label: {
					Group {
						if isSaving || isRequestingCalendarPermission {
							ProgressView()
								.tint(.white)
						} else {
							Text("Save & Continue")
								.font(.headline)
								.fontWeight(.bold)
						}
					}
					.frame(maxWidth: .infinity)
					.frame(height: 54)
					.foregroundStyle(.white)
					.background(continueGradient, in: Capsule())
				}
				.buttonStyle(.plain)
				.disabled(isSaving || isRequestingCalendarPermission || !hasCompleteAvailability)
				.opacity(hasCompleteAvailability ? 1 : 0.45)
				.padding(.top, 24)
			}
			.padding(.horizontal, 32)
		}
		.scrollIndicators(.hidden)
		.safeAreaPadding(.top)
	}

	private var calendarPermissionIntro: some View {
		VStack(alignment: .leading, spacing: 20) {
			Spacer()

			Image(systemName: "calendar.badge.clock")
				.font(.system(size: 48, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
				.foregroundStyle(.orange)

			Text("Connect your calendar")
				.font(.system(size: 36, weight: .bold, design: .rounded))
				.foregroundStyle(foregroundColor)

			Text("Kismet first marks your calendar events as busy in orange. Then you can add your free hours in green.")
				.font(.body)
				.foregroundStyle(foregroundColor.opacity(0.76))
				.fixedSize(horizontal: false, vertical: true)

			Spacer()

			Button {
				Task {
					await requestInitialCalendarAccess()
				}
			} label: {
				Group {
					if isRequestingCalendarPermission {
						ProgressView()
							.tint(.white)
					} else {
						Text("Continue with Calendar")
							.font(.headline)
							.fontWeight(.bold)
					}
				}
				.frame(maxWidth: .infinity)
				.frame(height: 54)
				.foregroundStyle(.white)
				.background(continueGradient, in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(isRequestingCalendarPermission)
		}
		.padding(.horizontal, 32)
		.safeAreaPadding(.vertical, 32)
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("When are you\nusually free?")
				.font(.system(size: 36, weight: .bold, design: .rounded))
				.fontWidth(.expanded)
				.foregroundStyle(foregroundColor)

			Text("This helps friends know the best time to reach out.")
				.font(.body)
				.foregroundStyle(foregroundColor.opacity(0.76))
		}
	}

	private var legend: some View {
		HStack(spacing: 16) {
			legendItem(color: .green, title: "Free")
			legendItem(color: .orange, title: "Busy")
			legendItem(color: foregroundColor.opacity(0.18), title: "Unset")
		}
		.font(.caption)
		.foregroundStyle(foregroundColor.opacity(0.72))
	}

	private func legendItem(color: Color, title: String) -> some View {
		HStack(spacing: 6) {
			Capsule()
				.fill(color)
				.frame(width: 12, height: 8)
			Text(title)
		}
	}

	@MainActor
	private func requestInitialCalendarAccess() async {
		isRequestingCalendarPermission = true
		defer { isRequestingCalendarPermission = false }

		if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
			_ = try? await eventStore.requestFullAccessToEvents()
		}

		await refreshBusyFromCalendar()
		withAnimation(.easeInOut(duration: 0.35)) {
			isCalendarStepComplete = true
		}
	}

	@MainActor
	private func saveAvailability() async {
		isRequestingCalendarPermission = true
		defer { isRequestingCalendarPermission = false }

		await refreshBusyFromCalendar()
		onFinish(
			AvailabilitySetupRequestDTO(
				weekdayAvailability: weekdayAvailability,
				weekendAvailability: weekendAvailability,
				timeZoneId: TimeZone.current.identifier,
				dailyAvailability: dailyWindows.map {
					DailyAvailabilityDTO(
						day: $0.day.rawValue,
						startMinutes: $0.startMinutes,
						endMinutes: $0.endMinutes,
						busySegments: $0.busySegments.map {
							BusySegmentDTO(startMinutes: $0.startMinutes, endMinutes: $0.endMinutes)
						}
					)
				}
			)
		)
	}

	@MainActor
	private func refreshBusyFromCalendar() async {
		guard hasCalendarAccess else { return }

		let calendar = Calendar.current
		let startOfToday = calendar.startOfDay(for: .now)
		guard let endDate = calendar.date(byAdding: .day, value: 7, to: startOfToday) else { return }

		let predicate = eventStore.predicateForEvents(
			withStart: startOfToday,
			end: endDate,
			calendars: nil
		)
		let events = eventStore.events(matching: predicate)

		var busyByDay: [AvailabilityDay.Day: [BusySegment]] = Dictionary(
			uniqueKeysWithValues: AvailabilityDay.Day.allCases.map { ($0, []) }
		)

		for dayOffset in 0..<7 {
			guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
			      let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
			      let day = AvailabilityDay.Day.from(date: dayStart, calendar: calendar) else {
				continue
			}

			for event in events where event.endDate > dayStart && event.startDate < dayEnd {
				let startMinutes = event.isAllDay || event.startDate <= dayStart
					? 6 * 60
					: max(minutesSinceMidnight(event.startDate, calendar: calendar), 6 * 60)
				let endMinutes = event.isAllDay || event.endDate >= dayEnd
					? 24 * 60
					: min(minutesSinceMidnight(event.endDate, calendar: calendar), 24 * 60)

				guard startMinutes < endMinutes else { continue }
				busyByDay[day, default: []].append(
					BusySegment(startMinutes: startMinutes, endMinutes: endMinutes)
				)
			}
		}

		for index in dailyWindows.indices {
			let day = dailyWindows[index].day
			dailyWindows[index].busySegments = mergeSegments(busyByDay[day] ?? [])
		}
	}

	private var hasCalendarAccess: Bool {
		switch EKEventStore.authorizationStatus(for: .event) {
		case .fullAccess, .authorized:
			true
		default:
			false
		}
	}

	private func mergeSegments(_ segments: [BusySegment]) -> [BusySegment] {
		let sorted = segments.sorted { $0.startMinutes < $1.startMinutes }
		var merged: [BusySegment] = []
		for segment in sorted {
			guard let last = merged.last else {
				merged.append(segment)
				continue
			}
			if segment.startMinutes <= last.endMinutes {
				merged[merged.count - 1].endMinutes = max(last.endMinutes, segment.endMinutes)
			} else {
				merged.append(segment)
			}
		}
		return merged
	}

	private var customHoursSheet: some View {
		NavigationStack {
			List {
				ForEach($dailyWindows) { $window in
					VStack(alignment: .leading, spacing: 10) {
						Text(window.day.fullName)
							.font(.headline)

						HStack {
							DatePicker(
								"From",
								selection: startTimeBinding(for: $window),
								displayedComponents: .hourAndMinute
							)

							DatePicker(
								"To",
								selection: endTimeBinding(for: $window),
								displayedComponents: .hourAndMinute
							)
						}
						.font(.subheadline)
					}
					.padding(.vertical, 4)
				}
			}
			.navigationTitle("Hours by Day")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") {
						weekdayAvailability = "Custom"
						weekendAvailability = "Custom"
						for index in dailyWindows.indices {
							dailyWindows[index].isConfigured = true
						}
						isShowingCustomHours = false
					}
				}
			}
		}
		.presentationDetents([.large])
	}

	private func availabilityMenu(
		title: String,
		value: String,
		options: [String],
		onSelect: @escaping (String) -> Void
	) -> some View {
		Menu {
			ForEach(options, id: \.self) { option in
				Button(option) {
					onSelect(option)
				}
			}
		} label: {
			availabilityRow(title: title, value: value)
		}
		.buttonStyle(.plain)
	}

	private func availabilityRow(
		title: String,
		value: String,
		showsDetailBelow: Bool = false
	) -> some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.headline)
					.fontWeight(.semibold)
					.foregroundStyle(foregroundColor)

				if showsDetailBelow {
					Text(value)
						.font(.subheadline)
						.foregroundStyle(foregroundColor.opacity(0.64))
				}
			}

			Spacer()

			if !showsDetailBelow {
				Text(value)
					.font(.subheadline)
					.foregroundStyle(foregroundColor.opacity(0.68))
			}

			Image(systemName: "chevron.right")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(foregroundColor.opacity(0.42))
				.accessibilityHidden(true)
		}
		.padding(.horizontal, 20)
		.frame(maxWidth: .infinity)
		.frame(height: showsDetailBelow ? 82 : 72)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
		.overlay {
			RoundedRectangle(cornerRadius: 20)
				.stroke(foregroundColor.opacity(0.12), lineWidth: 1)
		}
		.contentShape(Rectangle())
	}

	private func applyWeekdayPreset(_ option: String) {
		weekdayAvailability = option
		let start = switch option {
		case "After 5:00 PM": 17 * 60
		case "After 7:00 PM": 19 * 60
		case "Anytime": 6 * 60
		default: 18 * 60
		}

		for index in dailyWindows.indices where index < 5 {
			dailyWindows[index].startMinutes = start
			dailyWindows[index].endMinutes = 24 * 60
			dailyWindows[index].isConfigured = true
		}
	}

	private func applyWeekendPreset(_ option: String) {
		weekendAvailability = option
		let range = switch option {
		case "Mornings": (6 * 60, 12 * 60)
		case "Afternoons": (12 * 60, 17 * 60)
		case "Evenings": (17 * 60, 24 * 60)
		default: (6 * 60, 24 * 60)
		}

		for index in dailyWindows.indices where index >= 5 {
			dailyWindows[index].startMinutes = range.0
			dailyWindows[index].endMinutes = range.1
			dailyWindows[index].isConfigured = true
		}
	}

	private var hasCompleteAvailability: Bool {
		dailyWindows.allSatisfy(\.isConfigured)
	}

	private func startTimeBinding(for window: Binding<AvailabilityDay>) -> Binding<Date> {
		Binding(
			get: { date(for: window.wrappedValue.startMinutes) },
			set: { date in
				let minutes = minutesSinceMidnight(date)
				window.wrappedValue.startMinutes = min(max(minutes, 6 * 60), window.wrappedValue.endMinutes - 30)
			}
		)
	}

	private func endTimeBinding(for window: Binding<AvailabilityDay>) -> Binding<Date> {
		Binding(
			get: { date(for: window.wrappedValue.endMinutes) },
			set: { date in
				var minutes = minutesSinceMidnight(date)
				if minutes == 0 {
					minutes = 24 * 60
				}
				window.wrappedValue.endMinutes = max(
					min(minutes, 24 * 60),
					window.wrappedValue.startMinutes + 30
				)
			}
		)
	}

	private func date(for minutes: Int) -> Date {
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: .now)
		return calendar.date(byAdding: .minute, value: minutes, to: startOfDay) ?? startOfDay
	}

	private func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
		let components = calendar.dateComponents([.hour, .minute], from: date)
		return (components.hour ?? 0) * 60 + (components.minute ?? 0)
	}
}

private struct WeekAvailabilityChart: View {
	let dailyWindows: [AvailabilityDay]
	let foregroundColor: Color

	private let timelineStart = 6 * 60
	private let timelineEnd = 24 * 60

	var body: some View {
		HStack(alignment: .bottom, spacing: 10) {
			VStack {
				Text("6 AM")
					.frame(maxHeight: .infinity, alignment: .top)
				Text("12 AM")
			}
			.font(.caption2)
			.foregroundStyle(foregroundColor.opacity(0.52))
			.frame(height: 132)

			HStack(alignment: .bottom, spacing: 0) {
				ForEach(dailyWindows) { window in
					VStack(spacing: 9) {
						Text(window.day.shortName)
							.font(.subheadline)
							.fontWeight(.semibold)
							.foregroundStyle(foregroundColor.opacity(0.82))

						AvailabilityBar(
							window: window,
							timelineStart: timelineStart,
							timelineEnd: timelineEnd,
							freeColor: .green,
							busyColor: .orange,
							trackColor: foregroundColor.opacity(0.14)
						)
						.frame(width: 22, height: 108)
					}
					.frame(maxWidth: .infinity)
				}
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Availability from 6 AM to midnight. Green is free, orange is busy.")
	}
}

private struct AvailabilityBar: View {
	let window: AvailabilityDay
	let timelineStart: Int
	let timelineEnd: Int
	let freeColor: Color
	let busyColor: Color
	let trackColor: Color

	var body: some View {
		GeometryReader { proxy in
			let total = CGFloat(timelineEnd - timelineStart)

			ZStack(alignment: .top) {
				Capsule()
					.fill(trackColor)

				if window.isConfigured {
					segment(
						start: window.startMinutes,
						end: window.endMinutes,
						total: total,
						height: proxy.size.height,
						color: freeColor
					)
				}

				ForEach(Array(window.busySegments.enumerated()), id: \.offset) { _, busy in
					segment(
						start: busy.startMinutes,
						end: busy.endMinutes,
						total: total,
						height: proxy.size.height,
						color: busyColor
					)
				}
			}
			.clipShape(Capsule())
		}
	}

	@ViewBuilder
	private func segment(
		start: Int,
		end: Int,
		total: CGFloat,
		height: CGFloat,
		color: Color
	) -> some View {
		let clippedStart = max(start, timelineStart)
		let clippedEnd = min(end, timelineEnd)
		if clippedStart < clippedEnd {
			let y = height * CGFloat(clippedStart - timelineStart) / total
			let segmentHeight = max(3, height * CGFloat(clippedEnd - clippedStart) / total)
			Capsule()
				.fill(color)
				.frame(height: segmentHeight)
				.offset(y: y)
		}
	}
}

private struct BusySegment {
	var startMinutes: Int
	var endMinutes: Int
}

private struct AvailabilityDay: Identifiable {
	enum Day: String, CaseIterable {
		case monday
		case tuesday
		case wednesday
		case thursday
		case friday
		case saturday
		case sunday

		var shortName: String {
			switch self {
			case .monday: "M"
			case .tuesday: "T"
			case .wednesday: "W"
			case .thursday: "T"
			case .friday: "F"
			case .saturday: "S"
			case .sunday: "S"
			}
		}

		var fullName: String {
			rawValue.capitalized
		}

		static func from(date: Date, calendar: Calendar) -> Day? {
			switch calendar.component(.weekday, from: date) {
			case 2: .monday
			case 3: .tuesday
			case 4: .wednesday
			case 5: .thursday
			case 6: .friday
			case 7: .saturday
			case 1: .sunday
			default: nil
			}
		}
	}

	let day: Day
	var startMinutes: Int
	var endMinutes: Int
	var isConfigured = false
	var busySegments: [BusySegment] = []

	var id: Day { day }

	static let defaults = Day.allCases.map { day in
		AvailabilityDay(
			day: day,
			startMinutes: day == .saturday || day == .sunday ? 6 * 60 : 18 * 60,
			endMinutes: 24 * 60
		)
	}
}

#Preview("Dark") {
	AvailabilitySetupView()
		.preferredColorScheme(.dark)
}

#Preview("Light") {
	AvailabilitySetupView()
		.preferredColorScheme(.light)
}
