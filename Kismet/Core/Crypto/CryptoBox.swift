import CryptoKit
import Foundation

enum CryptoBoxError: LocalizedError {
	case missingPrivateKey
	case invalidPublicKey
	case invalidEnvelope
	case unsupportedVersion(UInt8)
	case sealingFailed
	case openingFailed
	case encodingFailed

	var errorDescription: String? {
		switch self {
		case .missingPrivateKey:
			return "Encryption key is missing."
		case .invalidPublicKey:
			return "Friend public key is invalid."
		case .invalidEnvelope:
			return "Encrypted location blob is malformed."
		case .unsupportedVersion(let version):
			return "Unsupported location blob version (\(version))."
		case .sealingFailed:
			return "Could not encrypt location."
		case .openingFailed:
			return "Could not decrypt location."
		case .encodingFailed:
			return "Could not encode location payload."
		}
	}
}

/// X25519 identity key + ChaCha20-Poly1305 sealed location blobs.
/// Ciphertext is opaque to the server: `base64(version || ChaChaPoly.combined)`.
actor CryptoBox {
	static let shared = CryptoBox()

	private static let envelopeVersion: UInt8 = 1
	private static let hkdfSalt = Data("kismet-location-v1".utf8)
	private static let locationKind = "LOCATION"

	private var cachedPrivateKey: Curve25519.KeyAgreement.PrivateKey?

	/// Ensures a local identity key exists and is published to `PUT /me/public-key`.
	@discardableResult
	func ensurePublished(using client: APIClient) async throws -> MeResponseDTO {
		let me: MeResponseDTO = try await client.get("/me")
		let privateKey = try loadOrCreatePrivateKey()
		let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
		let serverVersion = me.keyVersion ?? 0
		let serverPublicKey = me.publicKey

		// Idempotent: this device's key is already on the server.
		if serverPublicKey == publicKeyBase64, serverVersion >= 1 {
			try KeychainStore.set(String(serverVersion), for: .x25519KeyVersion)
			return me
		}

		let nextVersion: Int
		if serverPublicKey == nil || serverPublicKey?.isEmpty == true {
			nextVersion = 1
		} else {
			// Local key was wiped (sign-out / reinstall) — bump past the stored version.
			nextVersion = serverVersion + 1
		}

		let updated: MeResponseDTO = try await client.put(
			"/me/public-key",
			body: PublicKeyRequestDTO(publicKey: publicKeyBase64, keyVersion: nextVersion)
		)
		try KeychainStore.set(String(nextVersion), for: .x25519KeyVersion)
		return updated
	}

	func publicKeyBase64() throws -> String {
		try loadOrCreatePrivateKey().publicKey.rawRepresentation.base64EncodedString()
	}

	func keyVersion() -> Int {
		storedKeyVersion() ?? 1
	}

	func sealLocation(
		_ payload: LocationPayloadDTO,
		senderUserId: String,
		recipientUserId: String,
		recipientPublicKeyBase64: String,
		recipientKeyVersion: Int
	) throws -> String {
		let privateKey = try loadOrCreatePrivateKey()
		let recipientPublicKey = try publicKey(from: recipientPublicKeyBase64)
		let symmetricKey = try deriveSymmetricKey(
			privateKey: privateKey,
			peerPublicKey: recipientPublicKey,
			senderUserId: senderUserId,
			recipientUserId: recipientUserId,
			recipientKeyVersion: recipientKeyVersion
		)

		let plaintext = try APIConfig.jsonEncoder.encode(payload)
		let aad = authenticationData(
			senderUserId: senderUserId,
			recipientUserId: recipientUserId,
			recipientKeyVersion: recipientKeyVersion
		)

		do {
			let sealed = try ChaChaPoly.seal(plaintext, using: symmetricKey, authenticating: aad)
			var envelope = Data([Self.envelopeVersion])
			envelope.append(sealed.combined)
			return envelope.base64EncodedString()
		} catch {
			throw CryptoBoxError.sealingFailed
		}
	}

	func openLocation(
		ciphertextBase64: String,
		senderUserId: String,
		recipientUserId: String,
		senderPublicKeyBase64: String,
		recipientKeyVersion: Int
	) throws -> LocationPayloadDTO {
		guard let envelope = Data(base64Encoded: ciphertextBase64), envelope.count > 1 else {
			throw CryptoBoxError.invalidEnvelope
		}

		let version = envelope[envelope.startIndex]
		guard version == Self.envelopeVersion else {
			throw CryptoBoxError.unsupportedVersion(version)
		}

		let privateKey = try loadOrCreatePrivateKey()
		let senderPublicKey = try publicKey(from: senderPublicKeyBase64)
		let symmetricKey = try deriveSymmetricKey(
			privateKey: privateKey,
			peerPublicKey: senderPublicKey,
			senderUserId: senderUserId,
			recipientUserId: recipientUserId,
			recipientKeyVersion: recipientKeyVersion
		)

		let aad = authenticationData(
			senderUserId: senderUserId,
			recipientUserId: recipientUserId,
			recipientKeyVersion: recipientKeyVersion
		)

		do {
			let sealed = try ChaChaPoly.SealedBox(combined: envelope.dropFirst())
			let plaintext = try ChaChaPoly.open(sealed, using: symmetricKey, authenticating: aad)
			return try APIConfig.jsonDecoder.decode(LocationPayloadDTO.self, from: plaintext)
		} catch {
			throw CryptoBoxError.openingFailed
		}
	}

	/// Drops the local identity key. Next publish must bump `keyVersion`.
	func clearLocalKeys() {
		cachedPrivateKey = nil
		KeychainStore.clearCryptoKeys()
	}

	// MARK: - Private

	private func loadOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
		if let cachedPrivateKey {
			return cachedPrivateKey
		}

		if let existing = KeychainStore.get(.x25519PrivateKey),
		   let data = Data(base64Encoded: existing),
		   let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
			cachedPrivateKey = key
			return key
		}

		let key = Curve25519.KeyAgreement.PrivateKey()
		try KeychainStore.set(key.rawRepresentation.base64EncodedString(), for: .x25519PrivateKey)
		if storedKeyVersion() == nil {
			try KeychainStore.set("1", for: .x25519KeyVersion)
		}
		cachedPrivateKey = key
		return key
	}

	private func storedKeyVersion() -> Int? {
		guard let raw = KeychainStore.get(.x25519KeyVersion), let value = Int(raw), value >= 1 else {
			return nil
		}
		return value
	}

	private func publicKey(from base64: String) throws -> Curve25519.KeyAgreement.PublicKey {
		guard let data = Data(base64Encoded: base64),
		      let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data) else {
			throw CryptoBoxError.invalidPublicKey
		}
		return key
	}

	private func deriveSymmetricKey(
		privateKey: Curve25519.KeyAgreement.PrivateKey,
		peerPublicKey: Curve25519.KeyAgreement.PublicKey,
		senderUserId: String,
		recipientUserId: String,
		recipientKeyVersion: Int
	) throws -> SymmetricKey {
		let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
		let info = Data("\(senderUserId)|\(recipientUserId)|\(recipientKeyVersion)".utf8)
		return sharedSecret.hkdfDerivedSymmetricKey(
			using: SHA256.self,
			salt: Self.hkdfSalt,
			sharedInfo: info,
			outputByteCount: 32
		)
	}

	private func authenticationData(
		senderUserId: String,
		recipientUserId: String,
		recipientKeyVersion: Int
	) -> Data {
		Data("\(senderUserId)|\(recipientUserId)|\(Self.locationKind)|\(recipientKeyVersion)".utf8)
	}
}
