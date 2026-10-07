import Foundation
import Security
import os

/// A ``SecretStore`` backed by the Keychain.
///
/// Each key is one generic-password item under a single service. Items are readable after the device's first
/// unlock, never leave the device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), and are excluded from
/// iCloud Keychain, so they are not in iCloud or device backups either.
public struct KeychainSecretStore: SecretStore {
    /// The Keychain service every item is saved under.
    public let service: String

    private static let logger = Logger(serafinCategory: "keychain")

    /// Creates a store.
    ///
    /// - Parameter service: The Keychain service for the items. Tests pass a unique one.
    public init(service: String = Logger.serafinSubsystem) {
        self.service = service
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw SerafinError.keychainDataCorrupt
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw failure(status, "read", key)
        }
    }

    public func set(_ value: String, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery(for: key).merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status, "write", key) }
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status, "delete", key) }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func failure(_ status: OSStatus, _ operation: StaticString, _ key: String) -> SerafinError {
        Self.logger.error(
            "Keychain \(operation, privacy: .public) failed for \(key, privacy: .private): \(status, privacy: .public)"
        )
        return .keychain(status: status)
    }
}
