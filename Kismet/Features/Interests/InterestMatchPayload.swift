import Foundation

/// Plaintext sealed inside INTEREST_MATCH blobs — server never sees interest ids.
struct InterestMatchPayloadDTO: Codable, Sendable, Equatable {
	var interestIds: [String]
	var updatedAt: Date
}
