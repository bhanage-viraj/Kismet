import Foundation
import Testing
@testable import Kismet

struct BumpHandshakeCodecTests {
	@Test func encodesAndDecodesHandshake() throws {
		let payload = BumpHandshakePayload(
			userId: "user-1",
			displayName: "Ada",
			publicKey: "base64-key",
			keyVersion: 2,
			appVersion: "1.0"
		)
		let data = try BumpHandshakeCodec.encode(BumpHandshakeCodec.handshakeEnvelope(payload))
		let decoded = try BumpHandshakeCodec.decode(data)

		#expect(decoded.type == .handshake)
		#expect(decoded.v == 1)
		#expect(decoded.handshake == payload)
	}

	@Test func encodesAndDecodesNiToken() throws {
		let data = try BumpHandshakeCodec.encode(
			BumpHandshakeCodec.niTokenEnvelope(tokenBase64: "dG9rZW4=")
		)
		let decoded = try BumpHandshakeCodec.decode(data)
		#expect(decoded.type == .niToken)
		#expect(decoded.tokenBase64 == "dG9rZW4=")
	}

	@Test func encodesAndDecodesPairAck() throws {
		let data = try BumpHandshakeCodec.encode(
			BumpHandshakeCodec.pairAckEnvelope(peerUserId: "user-9")
		)
		let decoded = try BumpHandshakeCodec.decode(data)
		#expect(decoded.type == .pairAck)
		#expect(decoded.peerUserId == "user-9")
	}

	@Test func rejectsUnsupportedVersion() throws {
		let envelope = BumpWireEnvelope(
			v: 99,
			type: .handshake,
			handshake: BumpHandshakePayload(
				userId: "u",
				displayName: "D",
				publicKey: "k",
				keyVersion: 1,
				appVersion: "1.0"
			),
			tokenBase64: nil,
			peerUserId: nil
		)
		let data = try JSONEncoder().encode(envelope)
		#expect(throws: BumpTransportError.self) {
			try BumpHandshakeCodec.decode(data)
		}
	}

	@Test func rejectsHandshakeMissingPayload() throws {
		let envelope = BumpWireEnvelope(
			v: 1,
			type: .handshake,
			handshake: nil,
			tokenBase64: nil,
			peerUserId: nil
		)
		let data = try JSONEncoder().encode(envelope)
		#expect(throws: BumpTransportError.self) {
			try BumpHandshakeCodec.decode(data)
		}
	}
}
