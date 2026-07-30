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
		return decoder
	}()

	static let jsonEncoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .useDefaultKeys
		return encoder
	}()
}
