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
///
/// Abstraction over Keychain reads/writes so `SettingsStore` can be given a fake in tests — the real
/// Keychain can't be made to return an arbitrary `OSStatus` on demand, which is what TASK-569 needs
/// to exercise the read-failure path.
public protocol KeychainAccess: Sendable {
    func set(_ value: String, forKey key: String) throws
    /// Returns the stored value, `nil` if the item is genuinely absent (`errSecItemNotFound`), and
    /// throws `KeychainError.readFailed` for any other non-success status.
    func read(_ key: String) throws -> String?
    /// Convenience that collapses any read failure to `nil` (for low-risk callers that don't care why).
    func get(_ key: String) -> String?
    func delete(_ key: String) throws
}

public extension KeychainAccess {
    func get(_ key: String) -> String? {
        (try? read(key)) ?? nil
    }
}

public struct KeychainStore: KeychainAccess {
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

    /// Reads a stored secret. `errSecItemNotFound` is a normal absence → `nil`; any other non-success
    /// status is surfaced as `KeychainError.readFailed` rather than collapsed to `nil`, so callers can
    /// tell a missing key from an inaccessible/locked/corrupted one (TASK-569).
    public func read(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.readFailed(status) }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status)
        }
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
    case readFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .addFailed(code): "Keychain write failed (code \(code))"
        case let .updateFailed(code): "Keychain update failed (code \(code))"
        case let .deleteFailed(code): "Keychain delete failed (code \(code))"
        case let .readFailed(code): "Keychain read failed (code \(code))"
        }
    }
}
