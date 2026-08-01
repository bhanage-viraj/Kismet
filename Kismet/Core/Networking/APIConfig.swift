import Foundation

enum APIConfig {
	#if targetEnvironment(simulator)
	static let baseURL = URL(string: "http://localhost:8080")!
	#else
	/// ngrok tunnel for physical-device development.
	static let baseURL = URL(string: "https://bristleless-nonhygroscopic-hans.ngrok-free.dev")!
	#endif

	static let jsonDecoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .useDefaultKeys
		decoder.dateDecodingStrategy = .custom(decodeISO8601Date)
		return decoder
	}()

	static let jsonEncoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .useDefaultKeys
		encoder.dateEncodingStrategy = .custom(encodeISO8601Date)
		return encoder
	}()

	/// WebSocket base derived from HTTP base (`http` → `ws`, `https` → `wss`).
	static var webSocketURL: URL {
		var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
		switch components.scheme?.lowercased() {
		case "https":
			components.scheme = "wss"
		default:
			components.scheme = "ws"
		}
		components.path = "/ws"
		return components.url!
	}
}

private let iso8601Fractional: ISO8601DateFormatter = {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
	return formatter
}()

private let iso8601Basic: ISO8601DateFormatter = {
	let formatter = ISO8601DateFormatter()
	formatter.formatOptions = [.withInternetDateTime]
	return formatter
}()

private func decodeISO8601Date(from decoder: Decoder) throws -> Date {
	let container = try decoder.singleValueContainer()
	let string = try container.decode(String.self)
	if let date = iso8601Fractional.date(from: string) ?? iso8601Basic.date(from: string) {
		return date
	}
	throw DecodingError.dataCorruptedError(
		in: container,
		debugDescription: "Invalid ISO-8601 date: \(string)"
	)
}

private func encodeISO8601Date(_ date: Date, to encoder: Encoder) throws {
	var container = encoder.singleValueContainer()
	try container.encode(iso8601Fractional.string(from: date))
}
