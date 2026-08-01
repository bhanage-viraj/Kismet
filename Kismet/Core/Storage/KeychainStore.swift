import Foundation
import Security

enum KeychainStore {
	enum Key: String {
		case accessToken
		case refreshToken
		case userId
		case appleUserId
		/// Apple only shares the person's name on the first authorization — keep a local copy.
		case cachedDisplayName
		case x25519PrivateKey
		case x25519KeyVersion
	}

	static func set(_ value: String, for key: Key) throws {
		let data = Data(value.utf8)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrAccount as String: key.rawValue,
			kSecAttrService as String: "com.kismet.app.auth",
		]

		SecItemDelete(query as CFDictionary)

		var attributes = query
		attributes[kSecValueData as String] = data
		attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

		let status = SecItemAdd(attributes as CFDictionary, nil)
		guard status == errSecSuccess else {
			throw KeychainError.unexpectedStatus(status)
		}
	}

	static func get(_ key: Key) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrAccount as String: key.rawValue,
			kSecAttrService as String: "com.kismet.app.auth",
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		guard status == errSecSuccess, let data = item as? Data else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}

	static func delete(_ key: Key) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrAccount as String: key.rawValue,
			kSecAttrService as String: "com.kismet.app.auth",
		]
		SecItemDelete(query as CFDictionary)
	}

	static func clearAuth() {
		delete(.accessToken)
		delete(.refreshToken)
		delete(.userId)
		delete(.appleUserId)
	}

	static func clearCryptoKeys() {
		delete(.x25519PrivateKey)
		delete(.x25519KeyVersion)
	}

	enum KeychainError: Error {
		case unexpectedStatus(OSStatus)
	}
}
