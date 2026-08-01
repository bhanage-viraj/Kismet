import EventKit
import Foundation

struct CalendarContextProvider: ContextProviding {
	func current() async -> CalendarSlice {
		let store = EKEventStore()
		let status = EKEventStore.authorizationStatus(for: .event)

		guard status == .fullAccess else {
			return CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: nil)
		}

		let now = Date()
		let windowEnd = now.addingTimeInterval(3 * 60 * 60)
		let predicate = store.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)
		let events = store.events(matching: predicate)
			.filter { !$0.isAllDay }
			.sorted { $0.startDate < $1.startDate }

		guard let first = events.first else {
			return CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: windowEnd)
		}

		if first.startDate <= now, first.endDate > now {
			return CalendarSlice(isBusyNow: true, nextFreeAt: first.endDate, freeUntil: nil)
		}

		return CalendarSlice(isBusyNow: false, nextFreeAt: nil, freeUntil: first.startDate)
	}
}
