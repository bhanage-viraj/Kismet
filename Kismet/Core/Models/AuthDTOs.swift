import Foundation

struct AppleAuthRequestDTO: Encodable {
	struct FullName: Encodable {
		var givenName: String?
		var familyName: String?
	}

	var identityToken: String
	var fullName: FullName?
	var email: String?
	var interests: [String]
}

struct RefreshRequestDTO: Encodable {
	var refreshToken: String
}

struct InterestsRequestDTO: Encodable {
	var interests: [String]
}

struct DisplayNameRequestDTO: Encodable {
	var displayName: String
}

struct AvailabilitySetupRequestDTO: Encodable {
	var weekdayAvailability: String
	var weekendAvailability: String
	var timeZoneId: String?
	var dailyAvailability: [DailyAvailabilityDTO]
}

struct DailyAvailabilityDTO: Encodable {
	var day: String
	var startMinutes: Int
	var endMinutes: Int
	var busySegments: [BusySegmentDTO]
}

struct BusySegmentDTO: Codable {
	var startMinutes: Int
	var endMinutes: Int
}

struct AuthResponseDTO: Decodable {
	struct User: Decodable {
		var id: String
		var displayName: String?
		var email: String?
		var interests: [String]
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
	var interests: [String]
	var weekdayAvailability: String?
	var weekendAvailability: String?
	var timeZoneId: String?
	var publicKey: String?
	var keyVersion: Int?
	var onboardingCompleted: Bool
}

struct APIErrorResponse: Decodable {
	var status: Int?
	var message: String?
}
