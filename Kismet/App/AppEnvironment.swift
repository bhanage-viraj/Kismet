import Foundation

@MainActor
final class AppEnvironment {
	let authSession: AuthSession
	let apiClient: APIClient

	init(authSession: AuthSession? = nil, apiClient: APIClient = .shared) {
		self.apiClient = apiClient
		self.authSession = authSession ?? AuthSession(client: apiClient)
	}

	static let shared = AppEnvironment()
}
