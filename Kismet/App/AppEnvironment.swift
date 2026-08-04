import Foundation
import SwiftData

@MainActor
final class AppEnvironment {
	let authSession: AuthSession
	let apiClient: APIClient
	let locationManager: VisitLocationManager
	let mapFriendsStore: MapFriendsStore
	let friendsStore: FriendsStore
	let locationSharing: LocationSharingService
	let backgroundProximity: BackgroundProximityController
	let realtimeClient: RealtimeClient
	let suggestionEngine: SuggestionEngine
	let pulsePublisher: PulsePublisher
	let mapWeather: MapWeatherController
	let weatherObstacles: WeatherObstacleStore
	let meetupModelContainer: ModelContainer
	let meetupMemoryStore: MeetupMemoryStore
	let presenceMode: PresenceModeStore

	init(
		authSession: AuthSession? = nil,
		apiClient: APIClient = .shared,
		locationManager: VisitLocationManager? = nil,
		mapFriendsStore: MapFriendsStore? = nil,
		friendsStore: FriendsStore? = nil,
		locationSharing: LocationSharingService? = nil,
		realtimeClient: RealtimeClient? = nil,
		suggestionEngine: SuggestionEngine? = nil,
		pulsePublisher: PulsePublisher? = nil,
		mapWeather: MapWeatherController? = nil,
		weatherObstacles: WeatherObstacleStore? = nil,
		meetupModelContainer: ModelContainer? = nil,
		presenceMode: PresenceModeStore? = nil
	) {
		self.apiClient = apiClient
		self.authSession = authSession ?? AuthSession(client: apiClient)
		let resolvedLocationManager = locationManager ?? VisitLocationManager()
		let resolvedMapFriendsStore = mapFriendsStore ?? MapFriendsStore(client: apiClient)
		let resolvedFriendsStore = friendsStore ?? FriendsStore(client: apiClient)
		let resolvedLocationSharing = locationSharing ?? LocationSharingService(client: apiClient)
		let resolvedPresenceMode = presenceMode ?? PresenceModeStore()
		self.locationManager = resolvedLocationManager
		self.mapFriendsStore = resolvedMapFriendsStore
		self.friendsStore = resolvedFriendsStore
		self.locationSharing = resolvedLocationSharing
		self.presenceMode = resolvedPresenceMode
		self.backgroundProximity = BackgroundProximityController(
			locationManager: resolvedLocationManager,
			locationSharing: resolvedLocationSharing,
			friendsStore: resolvedFriendsStore,
			mapFriendsStore: resolvedMapFriendsStore,
			presenceMode: resolvedPresenceMode
		)
		self.realtimeClient = realtimeClient ?? RealtimeClient()
		self.suggestionEngine = suggestionEngine ?? SuggestionEngine()
		self.pulsePublisher = pulsePublisher ?? PulsePublisher(client: apiClient)
		self.mapWeather = mapWeather ?? MapWeatherController()
		self.weatherObstacles = weatherObstacles ?? WeatherObstacleStore()

		let container: ModelContainer
		if let meetupModelContainer {
			container = meetupModelContainer
		} else {
			do {
				container = try MeetupModelContainer.make()
			} catch {
				// Last-resort in-memory store so intelligence never crashes launch.
				container = try! MeetupModelContainer.makeInMemoryFallback()
			}
		}
		self.meetupModelContainer = container
		self.meetupMemoryStore = MeetupMemoryStore(container: container)
	}

	static let shared = AppEnvironment()
}

private extension MeetupModelContainer {
	/// Always succeeds — used only if on-disk container creation fails.
	static func makeInMemoryFallback() throws -> ModelContainer {
		let configuration = ModelConfiguration(
			"KismetMeetupMemoryFallback",
			schema: schema,
			isStoredInMemoryOnly: true,
			cloudKitDatabase: .none
		)
		return try ModelContainer(for: schema, configurations: [configuration])
	}
}
