import Foundation

enum BumpHandshakeCodec {
	private static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		return encoder
	}()

	private static let decoder = JSONDecoder()

	static func encode(_ envelope: BumpWireEnvelope) throws -> Data {
		do {
			return try encoder.encode(envelope)
		} catch {
			throw BumpTransportError.encodingFailed
		}
	}

	static func decode(_ data: Data) throws -> BumpWireEnvelope {
		let envelope: BumpWireEnvelope
		do {
			envelope = try decoder.decode(BumpWireEnvelope.self, from: data)
		} catch {
			throw BumpTransportError.decodingFailed(error.localizedDescription)
		}
		guard envelope.v == BumpWireEnvelope.currentVersion else {
			throw BumpTransportError.unsupportedMessageVersion(envelope.v)
		}
		switch envelope.type {
		case .handshake:
			guard envelope.handshake != nil else {
				throw BumpTransportError.decodingFailed("missing handshake")
			}
		case .niToken:
			guard let token = envelope.tokenBase64, !token.isEmpty else {
				throw BumpTransportError.decodingFailed("missing ni token")
			}
		case .pairAck:
			guard let peerUserId = envelope.peerUserId, !peerUserId.isEmpty else {
				throw BumpTransportError.decodingFailed("missing pairAck peerUserId")
			}
		}
		return envelope
	}

	static func handshakeEnvelope(_ payload: BumpHandshakePayload) -> BumpWireEnvelope {
		BumpWireEnvelope(
			v: BumpWireEnvelope.currentVersion,
			type: .handshake,
			handshake: payload,
			tokenBase64: nil,
			peerUserId: nil
		)
	}

	static func niTokenEnvelope(tokenBase64: String) -> BumpWireEnvelope {
		BumpWireEnvelope(
			v: BumpWireEnvelope.currentVersion,
			type: .niToken,
			handshake: nil,
			tokenBase64: tokenBase64,
			peerUserId: nil
		)
	}

	static func pairAckEnvelope(peerUserId: String) -> BumpWireEnvelope {
		BumpWireEnvelope(
			v: BumpWireEnvelope.currentVersion,
			type: .pairAck,
			handshake: nil,
			tokenBase64: nil,
			peerUserId: peerUserId
		)
	}
}
