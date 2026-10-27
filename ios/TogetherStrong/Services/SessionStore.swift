import Foundation
import Security

@MainActor
protocol SessionStoring: AnyObject {
    func read() throws -> String?
    func write(_ token: String) throws
    func remove() throws
}

@MainActor
final class KeychainSessionStore: SessionStoring {
    private let service: String
    private let account: String

    init(origin: APIOrigin, service: String = "TogetherStrong.session") {
        account = origin.storageKey
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw StorageError.keychain(status == errSecSuccess ? errSecDecode : status) }
        return value
    }

    func write(_ token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw StorageError.keychain(added) }
        } else if status != errSecSuccess { throw StorageError.keychain(status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.keychain(status) }
    }
}

enum StorageError: Error, LocalizedError {
    case keychain(OSStatus), database
    var errorDescription: String? {
        switch self {
        case .keychain: "Could not access secure sign-in storage. Unlock your iPhone and retry."
        case .database: "Could not access workout storage on this iPhone. Please retry before leaving."
        }
    }
}
