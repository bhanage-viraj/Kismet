import Foundation

enum APIConfig {
	/// The hosted backend, reachable from both the Simulator and a physical device.
	/// Point this at `http://localhost:8080` to work against a server running locally,
	/// which also needs `APPLE_VERIFY_TOKEN=false` on that server for Simulator sign-in.
	static let baseURL = URL(string: "https://kismet-4kbu.onrender.com")!

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
