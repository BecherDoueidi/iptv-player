import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}

public final class KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account: String

    public init(service: String = "com.personal.iptvplayer", account: String = "xtream-credentials") {
        self.service = service
        self.account = account
    }

    public func save(_ credentials: XtreamCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        // Delete first so a repeat save doesn't collide with an existing item.
        SecItemDelete(query() as CFDictionary)
        var attributes = query()
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    public func loadCredentials() throws -> XtreamCredentials? {
        var lookupQuery = query()
        lookupQuery[kSecReturnData as String] = true
        lookupQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(lookupQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(XtreamCredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
