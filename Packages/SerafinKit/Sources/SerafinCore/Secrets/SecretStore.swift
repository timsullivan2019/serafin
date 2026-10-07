import Synchronization

/// Stores small secrets, such as access tokens, the device ID and certificate pins, as strings by key.
///
/// Serafin keeps every secret behind this protocol: ``KeychainSecretStore`` in the app and
/// ``InMemorySecretStore`` in tests.
public protocol SecretStore: Sendable {
    /// Returns the value saved for `key`, or nil when there is none.
    func get(_ key: String) throws -> String?

    /// Saves `value` for `key`, replacing any earlier value.
    func set(_ value: String, for key: String) throws

    /// Removes the value for `key`. Removing a key that has no value is not an error.
    func delete(_ key: String) throws
}

/// A ``SecretStore`` that keeps values in memory only, for tests and previews.
public final class InMemorySecretStore: SecretStore {
    private let values: Mutex<[String: String]>

    /// Creates a store, optionally with values already in it.
    ///
    /// - Parameter values: The starting values by key.
    public init(_ values: [String: String] = [:]) {
        self.values = Mutex(values)
    }

    public func get(_ key: String) -> String? {
        values.withLock { $0[key] }
    }

    public func set(_ value: String, for key: String) {
        values.withLock { $0[key] = value }
    }

    public func delete(_ key: String) {
        _ = values.withLock { $0.removeValue(forKey: key) }
    }
}
