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
	let realtimeClient: RealtimeClient
	let suggestionEngine: SuggestionEngine
	let pulsePublisher: PulsePublisher
	let meetupModelContainer: ModelContainer
	let meetupMemoryStore: MeetupMemoryStore

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
		meetupModelContainer: ModelContainer? = nil
	) {
		self.apiClient = apiClient
		self.authSession = authSession ?? AuthSession(client: apiClient)
		self.locationManager = locationManager ?? VisitLocationManager()
		self.mapFriendsStore = mapFriendsStore ?? MapFriendsStore(client: apiClient)
		self.friendsStore = friendsStore ?? FriendsStore(client: apiClient)
		self.locationSharing = locationSharing ?? LocationSharingService(client: apiClient)
		self.realtimeClient = realtimeClient ?? RealtimeClient()
		self.suggestionEngine = suggestionEngine ?? SuggestionEngine()
		self.pulsePublisher = pulsePublisher ?? PulsePublisher(client: apiClient)

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
