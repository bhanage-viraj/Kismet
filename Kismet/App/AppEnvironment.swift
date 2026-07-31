import Foundation

@MainActor
final class AppEnvironment {
	let authSession: AuthSession
	let apiClient: APIClient
	let locationManager: VisitLocationManager
	let mapFriendsStore: MapFriendsStore

	init(
		authSession: AuthSession? = nil,
		apiClient: APIClient = .shared,
		locationManager: VisitLocationManager? = nil,
		mapFriendsStore: MapFriendsStore? = nil
	) {
		self.apiClient = apiClient
		self.authSession = authSession ?? AuthSession(client: apiClient)
		self.locationManager = locationManager ?? VisitLocationManager()
		self.mapFriendsStore = mapFriendsStore ?? MapFriendsStore()
	}

	static let shared = AppEnvironment()
}
