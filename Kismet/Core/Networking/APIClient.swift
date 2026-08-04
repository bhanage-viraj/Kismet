import Foundation

enum APIClientError: LocalizedError {
	case invalidURL
	case invalidResponse
	case httpStatus(Int, String?)
	case decoding(Error)
	case unauthorized

	/// True only when the server rejected the credentials. A timeout or a 5xx says
	/// nothing about whether the session is still good.
	var isCredentialRejection: Bool {
		switch self {
		case .unauthorized:
			return true
		case .httpStatus(let code, _):
			return code == 401
		default:
			return false
		}
	}

	var errorDescription: String? {
		switch self {
		case .invalidURL:
			return "Invalid API URL."
		case .invalidResponse:
			return "Invalid server response."
		case .httpStatus(let code, let message):
			return message ?? "Request failed (\(code))."
		case .decoding:
			return "Could not read server response."
		case .unauthorized:
			return "Session expired. Please sign in again."
		}
	}
}

actor APIClient {
	static let shared = APIClient()

	/// Default session for normal API calls.
	private let session: URLSession
	/// Longer timeouts so a Render free-tier cold start (~2 min) can finish.
	private let coldStartSession: URLSession

	init(session: URLSession = .shared) {
		self.session = session
		let config = URLSessionConfiguration.ephemeral
		config.timeoutIntervalForRequest = 120
		config.timeoutIntervalForResource = 180
		config.waitsForConnectivity = true
		self.coldStartSession = URLSession(configuration: config)
	}

	func request<T: Decodable>(
		method: String,
		path: String,
		body: (any Encodable)? = nil,
		authorized: Bool = true,
		retryOnUnauthorized: Bool = true,
		allowColdStart: Bool = false
	) async throws -> T {
		let url = APIConfig.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
		var request = URLRequest(url: url)
		request.httpMethod = method
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try APIConfig.jsonEncoder.encode(AnyEncodable(body))
		}

		if authorized, let accessToken = KeychainStore.get(.accessToken) {
			request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
		}

		let activeSession = allowColdStart ? coldStartSession : session
		let (data, response) = try await activeSession.data(for: request)
		guard let http = response as? HTTPURLResponse else {
			throw APIClientError.invalidResponse
		}

		if http.statusCode == 401, authorized, retryOnUnauthorized {
			let refreshed = try await refreshTokens()
			if refreshed {
				return try await self.request(
					method: method,
					path: path,
					body: body,
					authorized: true,
					retryOnUnauthorized: false,
					allowColdStart: allowColdStart
				)
			}
			throw APIClientError.unauthorized
		}

		guard (200..<300).contains(http.statusCode) else {
			let message = try? APIConfig.jsonDecoder.decode(APIErrorResponse.self, from: data).message
			throw APIClientError.httpStatus(http.statusCode, message)
		}

		if T.self == EmptyResponse.self {
			return EmptyResponse() as! T
		}

		if data.isEmpty, T.self == EmptyResponse.self {
			return EmptyResponse() as! T
		}

		do {
			return try APIConfig.jsonDecoder.decode(T.self, from: data)
		} catch {
			throw APIClientError.decoding(error)
		}
	}

	/// Ping health so a sleeping Render free instance starts waking before sign-in.
	func wakeServer() async {
		do {
			let _: EmptyResponse = try await request(
				method: "GET",
				path: "/actuator/health",
				body: nil as String?,
				authorized: false,
				retryOnUnauthorized: false,
				allowColdStart: true
			)
		} catch {
			// Wake is best-effort; the real call retries below.
		}
	}

	/// Retries transient failures (timeouts / 502–504) that happen while Render is cold-starting.
	func requestWithTransientRetry<T: Decodable>(
		method: String,
		path: String,
		body: (any Encodable)? = nil,
		authorized: Bool = true,
		attempts: Int = 3
	) async throws -> T {
		var lastError: Error?
		for attempt in 1...max(attempts, 1) {
			do {
				return try await request(
					method: method,
					path: path,
					body: body,
					authorized: authorized,
					allowColdStart: true
				)
			} catch {
				lastError = error
				guard attempt < attempts, Self.isTransientFailure(error) else { throw error }
				try await Task.sleep(for: .seconds(Double(attempt) * 1.5))
			}
		}
		throw lastError ?? APIClientError.invalidResponse
	}

	private static func isTransientFailure(_ error: Error) -> Bool {
		if let api = error as? APIClientError {
			switch api {
			case .httpStatus(let code, _):
				return [408, 425, 429, 502, 503, 504].contains(code)
			case .invalidResponse:
				return true
			case .unauthorized, .invalidURL, .decoding:
				return false
			}
		}
		let ns = error as NSError
		guard ns.domain == NSURLErrorDomain else { return false }
		switch ns.code {
		case NSURLErrorTimedOut,
			NSURLErrorCannotConnectToHost,
			NSURLErrorNetworkConnectionLost,
			NSURLErrorDNSLookupFailed,
			NSURLErrorNotConnectedToInternet,
			NSURLErrorCannotFindHost:
			return true
		default:
			return false
		}
	}

	func post<T: Decodable>(_ path: String, body: some Encodable, authorized: Bool = true) async throws -> T {
		try await request(method: "POST", path: path, body: body, authorized: authorized)
	}

	func post<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
		try await request(method: "POST", path: path, body: nil as String?, authorized: authorized)
	}

	func get<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
		try await request(method: "GET", path: path, authorized: authorized)
	}

	func put<T: Decodable>(_ path: String, body: some Encodable, authorized: Bool = true) async throws -> T {
		try await request(method: "PUT", path: path, body: body, authorized: authorized)
	}

	func deleteEmpty(_ path: String, authorized: Bool = true) async throws {
		let _: EmptyResponse = try await request(
			method: "DELETE",
			path: path,
			body: nil as String?,
			authorized: authorized
		)
	}

	func postEmpty(_ path: String, authorized: Bool = true) async throws {
		let _: EmptyResponse = try await request(
			method: "POST",
			path: path,
			body: nil as String?,
			authorized: authorized
		)
	}

	@discardableResult
	func refreshTokens() async throws -> Bool {
		guard let refreshToken = KeychainStore.get(.refreshToken) else {
			return false
		}

		do {
			let response: AuthResponseDTO = try await request(
				method: "POST",
				path: "/auth/refresh",
				body: RefreshRequestDTO(refreshToken: refreshToken),
				authorized: false,
				retryOnUnauthorized: false
			)
			try KeychainStore.set(response.accessToken, for: .accessToken)
			try KeychainStore.set(response.refreshToken, for: .refreshToken)
			try KeychainStore.set(response.user.id, for: .userId)
			return true
		} catch {
			// Only the server rejecting the refresh token means the session is gone.
			// Discarding credentials on a timeout turns a brief outage into a forced
			// sign-in, and the tokens are still good on the next attempt.
			if (error as? APIClientError)?.isCredentialRejection == true {
				KeychainStore.clearAuth()
			}
			return false
		}
	}
}

struct EmptyResponse: Decodable {
	init() {}
}

private struct AnyEncodable: Encodable {
	private let encodeFunc: (Encoder) throws -> Void

	init(_ value: any Encodable) {
		self.encodeFunc = value.encode
	}

	func encode(to encoder: Encoder) throws {
		try encodeFunc(encoder)
	}
}
