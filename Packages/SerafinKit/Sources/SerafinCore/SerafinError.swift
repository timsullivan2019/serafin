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
    /// The text typed as a server address is not an http or https address.
    case invalidAddress
    /// The address uses plain HTTP to a public host, which Serafin refuses because the token would travel in the
    /// clear.
    case insecureTransport
    /// The server's certificate is not trusted and has not been pinned. Carries what the server presented, so the
    /// user can check and pin it.
    case untrustedCertificate(CertificateFingerprint)
    /// Nothing answered at the address.
    case serverUnreachable
    /// Something answered, but it is not a Jellyfin server.
    case notJellyfin
    /// The server runs a Jellyfin version older than Serafin supports, which it carries.
    case unsupportedServerVersion(String)
}
