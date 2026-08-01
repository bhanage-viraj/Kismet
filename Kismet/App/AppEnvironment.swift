import Foundation

@MainActor
final class AppEnvironment {
	let authSession: AuthSession
	let apiClient: APIClient
	let locationManager: VisitLocationManager
	let mapFriendsStore: MapFriendsStore
	let friendsStore: FriendsStore
	let locationSharing: LocationSharingService
	let realtimeClient: RealtimeClient

	init(
		authSession: AuthSession? = nil,
		apiClient: APIClient = .shared,
		locationManager: VisitLocationManager? = nil,
		mapFriendsStore: MapFriendsStore? = nil,
		friendsStore: FriendsStore? = nil,
		locationSharing: LocationSharingService? = nil,
		realtimeClient: RealtimeClient? = nil
	) {
		self.apiClient = apiClient
		self.authSession = authSession ?? AuthSession(client: apiClient)
		self.locationManager = locationManager ?? VisitLocationManager()
		self.mapFriendsStore = mapFriendsStore ?? MapFriendsStore(client: apiClient)
		self.friendsStore = friendsStore ?? FriendsStore(client: apiClient)
		self.locationSharing = locationSharing ?? LocationSharingService(client: apiClient)
		self.realtimeClient = realtimeClient ?? RealtimeClient()
	}

	static let shared = AppEnvironment()
}
