import Foundation

/// Failures from SerafinCore. SerafinFeatures maps each case to a message for the user; none of them is ever
/// shown raw.
public enum SerafinError: Error, Equatable, Sendable {
    /// The Keychain refused an operation, with the `OSStatus` it returned.
    case keychain(status: Int32)
    /// A Keychain item held data that is not a UTF-8 string.
    case keychainDataCorrupt
    /// The saved server list could not be read or written.
    case serverStoreUnavailable
}
