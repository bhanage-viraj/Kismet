import Foundation
import Observation

struct MapRealtimeEventDTO: Decodable, Sendable {
	var type: String
	var userId: String?
	var at: Date?
}

/// Minimal STOMP client over a raw WebSocket (`/ws`) for `/user/queue/map` events.
@Observable
@MainActor
final class RealtimeClient {
	private(set) var isConnected = false
	private(set) var lastErrorMessage: String?

	/// Fired on the main actor for each map queue event.
	var onMapEvent: ((MapRealtimeEventDTO) -> Void)?

	private let session: URLSession
	private var webSocketTask: URLSessionWebSocketTask?
	private var receiveTask: Task<Void, Never>?
	private var heartbeatTask: Task<Void, Never>?
	private var reconnectTask: Task<Void, Never>?
	private var wantsConnection = false
	private var frameBuffer = Data()
	private var reconnectAttempt = 0

	init(session: URLSession = .shared) {
		self.session = session
	}

	func connect() {
		wantsConnection = true
		reconnectAttempt = 0
		openSocket()
	}

	func disconnect() {
		wantsConnection = false
		reconnectTask?.cancel()
		reconnectTask = nil
		tearDownSocket(clearError: true)
	}

	// MARK: - Socket lifecycle

	private func openSocket() {
		tearDownSocket(clearError: false)

		guard let token = KeychainStore.get(.accessToken), !token.isEmpty else {
			lastErrorMessage = "Missing access token for realtime."
			return
		}

		let task = session.webSocketTask(with: APIConfig.webSocketURL)
		webSocketTask = task
		task.resume()

		sendStompConnect(accessToken: token)
		startReceiveLoop()
	}

	private func tearDownSocket(clearError: Bool) {
		receiveTask?.cancel()
		receiveTask = nil
		heartbeatTask?.cancel()
		heartbeatTask = nil
		webSocketTask?.cancel(with: .goingAway, reason: nil)
		webSocketTask = nil
		frameBuffer.removeAll(keepingCapacity: false)
		isConnected = false
		if clearError {
			lastErrorMessage = nil
		}
	}

	private func scheduleReconnect() {
		guard wantsConnection else { return }
		reconnectTask?.cancel()
		let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 4))))
		reconnectAttempt += 1
		reconnectTask = Task { [weak self] in
			try? await Task.sleep(for: .seconds(delay))
			guard let self, !Task.isCancelled, self.wantsConnection else { return }
			self.openSocket()
		}
	}

	// MARK: - STOMP send

	private func sendStompConnect(accessToken: String) {
		let host = APIConfig.baseURL.host ?? "localhost"
		let frame = """
		CONNECT
		accept-version:1.1,1.2
		host:\(host)
		heart-beat:10000,10000
		Authorization:Bearer \(accessToken)

		\0
		"""
		// Strip incidental indentation from the multiline literal; keep STOMP newlines.
		let normalized = frame
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.joined(separator: "\n")
		send(text: normalized)
	}

	private func sendSubscribe() {
		send(text: "SUBSCRIBE\nid:sub-map\ndestination:/user/queue/map\nack:auto\n\n\0")
	}

	private func send(text: String) {
		guard let webSocketTask else { return }
		webSocketTask.send(.string(text)) { [weak self] error in
			guard let error else { return }
			Task { @MainActor in
				self?.lastErrorMessage = error.localizedDescription
				self?.isConnected = false
				self?.scheduleReconnect()
			}
		}
	}

	private func startHeartbeat() {
		heartbeatTask?.cancel()
		heartbeatTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(for: .seconds(10))
				guard let self, !Task.isCancelled, self.wantsConnection, self.isConnected else { return }
				self.send(text: "\n")
			}
		}
	}

	// MARK: - Receive / parse

	private func startReceiveLoop() {
		receiveTask?.cancel()
		receiveTask = Task { [weak self] in
			guard let self else { return }
			while !Task.isCancelled, self.wantsConnection {
				guard let task = self.webSocketTask else { break }
				do {
					let message = try await task.receive()
					guard !Task.isCancelled else { break }
					await self.handle(message: message)
				} catch {
					guard !Task.isCancelled else { break }
					await MainActor.run {
						self.lastErrorMessage = error.localizedDescription
						self.isConnected = false
						self.scheduleReconnect()
					}
					break
				}
			}
		}
	}

	private func handle(message: URLSessionWebSocketTask.Message) async {
		switch message {
		case .string(let text):
			await handleIncoming(Data(text.utf8))
		case .data(let data):
			await handleIncoming(data)
		@unknown default:
			break
		}
	}

	private func handleIncoming(_ data: Data) async {
		// Heartbeat-only payloads.
		if data == Data("\n".utf8) || data.isEmpty {
			return
		}

		frameBuffer.append(data)

		while let nullIndex = frameBuffer.firstIndex(of: 0) {
			let frameData = frameBuffer.subdata(in: frameBuffer.startIndex..<nullIndex)
			let next = frameBuffer.index(after: nullIndex)
			frameBuffer.removeSubrange(frameBuffer.startIndex..<next)

			guard let frameText = String(data: frameData, encoding: .utf8)?
				.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
				.trimmingCharacters(in: .newlines),
				!frameText.isEmpty
			else {
				continue
			}

			await handleFrame(frameText)
		}
	}

	private func handleFrame(_ frame: String) async {
		let lines = frame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		guard let command = lines.first?.uppercased(), !command.isEmpty else { return }

		var headers: [String: String] = [:]
		var index = 1
		while index < lines.count {
			let line = lines[index]
			index += 1
			if line.isEmpty { break }
			if let separator = line.firstIndex(of: ":") {
				let key = String(line[..<separator])
				let value = String(line[line.index(after: separator)...])
				headers[key] = value
			}
		}
		let body = lines.dropFirst(index).joined(separator: "\n")

		switch command {
		case "CONNECTED":
			isConnected = true
			lastErrorMessage = nil
			reconnectAttempt = 0
			sendSubscribe()
			startHeartbeat()
		case "MESSAGE":
			guard let data = body.data(using: .utf8) else { return }
			do {
				let event = try APIConfig.jsonDecoder.decode(MapRealtimeEventDTO.self, from: data)
				onMapEvent?(event)
			} catch {
				lastErrorMessage = "Could not decode realtime event."
			}
		case "ERROR":
			isConnected = false
			lastErrorMessage = headers["message"] ?? body
			scheduleReconnect()
		default:
			break
		}
	}
}
