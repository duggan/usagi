import Foundation
import Security

/// Stores the Claude.ai `sessionKey` cookie value in the macOS Keychain.
enum SessionStore {
	private static let service = "ie.duggan.usagi.session"
	private static let account = "claude.ai"

	enum SessionStoreError: Error {
		case unexpectedStatus(OSStatus)
		case dataEncodingFailed
	}

	static func read() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)
		guard status == errSecSuccess,
		      let data = item as? Data,
		      let value = String(data: data, encoding: .utf8)
		else { return nil }
		return value
	}

	static func write(_ value: String) throws {
		guard let data = value.data(using: .utf8) else {
			throw SessionStoreError.dataEncodingFailed
		}

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let attributes: [String: Any] = [
			kSecValueData as String: data,
		]

		let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
		if updateStatus == errSecItemNotFound {
			var addQuery = query
			addQuery[kSecValueData as String] = data
			let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
			guard addStatus == errSecSuccess else {
				throw SessionStoreError.unexpectedStatus(addStatus)
			}
		} else if updateStatus != errSecSuccess {
			throw SessionStoreError.unexpectedStatus(updateStatus)
		}
	}

	@discardableResult
	static func delete() -> Bool {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		let status = SecItemDelete(query as CFDictionary)
		return status == errSecSuccess || status == errSecItemNotFound
	}
}
