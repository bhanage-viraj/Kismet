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
	let pulseInbox: PulseInboxStore
	let meetupModelContainer: ModelContainer
	let meetupMemoryStore: MeetupMemoryStore
	let interestSuggestionStore: InterestSuggestionStore
	let presenceMode: PresenceModeStore
	/// Last Pulse draft prepared by Intelligence / Siri (not sent until confirm).
	var pendingPulseDraft: PulseDraft?

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
		pulseInbox: PulseInboxStore? = nil,
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
		self.pulseInbox = pulseInbox ?? PulseInboxStore(client: apiClient)

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
		self.interestSuggestionStore = InterestSuggestionStore()
		self.meetupMemoryStore.attachSpotlightIndexer()
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
