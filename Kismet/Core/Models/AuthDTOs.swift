import Foundation

struct AppleAuthRequestDTO: Encodable {
	struct FullName: Encodable {
		var givenName: String?
		var familyName: String?
	}

	var identityToken: String
	var fullName: FullName?
	var email: String?
}

struct RefreshRequestDTO: Encodable {
	var refreshToken: String
}

struct AuthResponseDTO: Decodable {
	struct User: Decodable {
		var id: String
		var displayName: String?
		var email: String?
		var isNewUser: Bool
		var onboardingCompleted: Bool
	}

	var accessToken: String
	var refreshToken: String
	var expiresIn: Int64
	var user: User
}

struct MeResponseDTO: Decodable {
	var id: String
	var displayName: String?
	var email: String?
	var onboardingCompleted: Bool
}

struct APIErrorResponse: Decodable {
	var status: Int?
	var message: String?
}
