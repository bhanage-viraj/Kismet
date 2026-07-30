import Foundation

enum APIClientError: LocalizedError {
	case invalidURL
	case invalidResponse
	case httpStatus(Int, String?)
	case decoding(Error)
	case unauthorized

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

	private let session: URLSession

	init(session: URLSession = .shared) {
		self.session = session
	}

	func request<T: Decodable>(
		method: String,
		path: String,
		body: (any Encodable)? = nil,
		authorized: Bool = true,
		retryOnUnauthorized: Bool = true
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

		let (data, response) = try await session.data(for: request)
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
					retryOnUnauthorized: false
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

	func post<T: Decodable>(_ path: String, body: some Encodable, authorized: Bool = true) async throws -> T {
		try await request(method: "POST", path: path, body: body, authorized: authorized)
	}

	func get<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
		try await request(method: "GET", path: path, authorized: authorized)
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
			KeychainStore.clearAuth()
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
