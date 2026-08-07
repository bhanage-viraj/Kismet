import CoreLocation
import Foundation

struct ContextBuilder: Sendable {
	var userId: String?
	var displayName: String
	var interests: [String]
	var coordinate: CLLocationCoordinate2D
	var placeName: String?
	var people: [MapPerson]
	var learned: LearnedSlice = .empty

	func build() async -> KismetContext {
		async let location = LocationContextProvider(
			coordinate: coordinate,
			placeName: placeName,
			accuracy: nil
		).current()
		async let friends = FriendPresenceProvider(people: people).current()
		async let calendar = CalendarContextProvider().current()
		async let motion = MotionContextProvider().current()
		async let focus = FocusContextProvider().current()
		async let weather = WeatherContextProvider(coordinate: coordinate).current()

		let loc = await location
		let cal = await calendar

		return KismetContext(
			generatedAt: Date(),
			user: UserContextSlice(
				userId: userId,
				displayName: displayName,
				interests: interests,
				coordinate: loc.coordinate,
				placeName: loc.placeName,
				freeUntil: cal.freeUntil,
				isBusyNow: cal.isBusyNow
			),
			friends: await friends,
			calendar: cal,
			motion: await motion,
			focus: await focus,
			weather: await weather,
			learned: learned
		)
	}
}
