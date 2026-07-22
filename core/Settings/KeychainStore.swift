import Foundation
import Security

/// Stores secrets in the macOS Keychain.
///
/// **Explicit security policy for new items:**
/// - `kSecAttrSynchronizable = false` — never synced to iCloud Keychain; API keys are
///   device-local secrets. This is also enforced at the search level so reads never
///   accidentally match a synced copy.
/// - `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — declared
///   intent for data-protection keychain (iOS-style). On macOS's traditional login keychain
///   this attribute is informational (the item is protected by the user's login keychain
///   ACL), but it is set on every add so that items stored via the data-protection keychain
///   (e.g. in sandboxed MAS builds with `kSecUseDataProtectionKeychain`) carry the
///   explicit policy without code changes.
///
/// Existing items without these attributes are migrated on next `set(_:forKey:)` via
/// delete-then-add (SecItemUpdate cannot change accessibility or sync attributes in-place).
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "com.jobhunt-app.jobhunt") {
        self.service = service
    }

    public func set(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let searchQuery = baseQuery(for: key)

        if SecItemCopyMatching(searchQuery as CFDictionary, nil) == errSecSuccess {
            // Delete and re-add so the new item picks up the explicit security policy.
            // SecItemUpdate cannot change kSecAttrAccessible or kSecAttrSynchronizable.
            // Check the delete status (TASK-585): a failed delete otherwise surfaces later as a
            // cryptic errSecDuplicateItem from SecItemAdd, hiding the real root cause.
            let deleteStatus = SecItemDelete(searchQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw KeychainError.deleteFailed(deleteStatus)
            }
        }
        var addQuery = searchQuery
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecAttrSynchronizable] = kCFBooleanFalse
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.addFailed(status) }
    }

    public func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    private func baseQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
    }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case addFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .addFailed(code): "Keychain write failed (code \(code))"
        case let .updateFailed(code): "Keychain update failed (code \(code))"
        case let .deleteFailed(code): "Keychain delete failed (code \(code))"
        }
    }
}
