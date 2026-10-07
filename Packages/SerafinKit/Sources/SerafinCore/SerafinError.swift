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
    /// The device has no network connection, as in Airplane Mode, or cellular data is turned off for Serafin.
    case offline
    /// Nothing answered at the address.
    case serverUnreachable
    /// iOS refused plain HTTP to the address before Serafin could ask. It allows HTTP only to local addresses and
    /// bare names, so a Tailscale 100.x address needs the server's Tailscale name, or HTTPS.
    case plainHTTPBlocked
    /// Something answered, but it is not a Jellyfin server.
    case notJellyfin
    /// The server runs a Jellyfin version older than Serafin supports, which it carries.
    case unsupportedServerVersion(String)
    /// The server refused the username and password.
    case invalidCredentials
    /// Quick Connect is turned off on this server, so the user signs in with a password instead.
    case quickConnectDisabled
    /// The Quick Connect code expired before anyone approved it.
    case quickConnectExpired
    /// There is no saved sign-in for that user on that server, or the server no longer accepts it, so they need to
    /// sign in again.
    case notSignedIn
    /// The item is no longer on the server.
    case notFound
    /// The server answered in a way Serafin does not expect, such as an error status or a reply without a token.
    /// Carries the HTTP status when there was one.
    case unexpectedResponse(status: Int?)
}
