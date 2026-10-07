import CryptoKit
import Foundation
import Security
import Synchronization
import os

/// What a server's certificate looks like, for showing to the user and for pinning.
public struct CertificateFingerprint: Hashable, Sendable {
    /// SHA-256 of the whole certificate in colon-separated hex, the form browsers and `openssl` show, so the user
    /// can compare it with what their server reports.
    public let certificateSHA256: String
    /// SHA-256 of the certificate's public key. Serafin pins this, so a renewed certificate with the same key keeps
    /// working.
    public let publicKeySHA256: String

    /// Reads the fingerprints of `certificate`, or returns nil when its public key cannot be read.
    public init?(certificate: SecCertificate) {
        guard
            let key = SecCertificateCopyKey(certificate),
            let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else { return nil }
        certificateSHA256 = Self.hex(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
        publicKeySHA256 = Self.hex(SHA256.hash(data: keyData))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// The certificate pins the user has accepted, one per host, kept in the ``SecretStore``.
public struct PinStore: Sendable {
    private let secrets: any SecretStore

    /// Creates a pin store.
    ///
    /// - Parameter secrets: Where pins are kept, under keys of the form `pin.<host>`.
    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    /// The pinned public-key hash for `host`, if the user has pinned one.
    public func pin(for host: String) throws -> String? {
        try secrets.get(Self.key(for: host))
    }

    /// Pins the public key of `fingerprint` for `host`.
    public func setPin(_ fingerprint: CertificateFingerprint, for host: String) throws {
        try secrets.set(fingerprint.publicKeySHA256, for: Self.key(for: host))
    }

    /// Forgets the pin for `host`.
    public func removePin(for host: String) throws {
        try secrets.delete(Self.key(for: host))
    }

    private static func key(for host: String) -> String {
        "pin.\(host.lowercased())"
    }
}

/// Accepts a server whose certificate the system trusts, or whose public key matches the user's pin for that host,
/// and refuses everything else.
///
/// This is how self-signed servers work without any global App Transport Security exception: the first connection
/// fails, ``rejectedCertificate(for:)`` shows the user what the server presented, the user pins it, and the retry
/// succeeds.
public final class PinningDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    /// What the delegate decided for one server trust challenge.
    enum Decision: Equatable {
        /// The system trusts the certificate, so normal handling applies.
        case systemTrusted
        /// The system does not trust it, but its key matches the pin.
        case pinned
        /// Not trusted and not pinned, with what the server presented.
        case rejected(CertificateFingerprint?)
    }

    private static let logger = Logger(serafinCategory: "pinning")
    private let pins: PinStore
    private let rejected = Mutex<[String: CertificateFingerprint]>([:])

    /// Creates the delegate.
    ///
    /// - Parameter pins: The pins to accept.
    public init(pins: PinStore) {
        self.pins = pins
    }

    /// The certificate `host` presented the last time it was refused, for the user to check before pinning it.
    public func rejectedCertificate(for host: String) -> CertificateFingerprint? {
        rejected.withLock { $0[host.lowercased()] }
    }

    /// Forgets the refused certificate for `host`, so a later failure is not blamed on an earlier refusal.
    func forgetRejection(for host: String) {
        rejected.withLock { $0[host.lowercased()] = nil }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        switch evaluate(trust, host: challenge.protectionSpace.host) {
        case .systemTrusted:
            completionHandler(.performDefaultHandling, nil)
        case .pinned:
            completionHandler(.useCredential, URLCredential(trust: trust))
        case .rejected:
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// Decides one server trust challenge for `host`.
    func evaluate(_ trust: SecTrust, host: String) -> Decision {
        if SecTrustEvaluateWithError(trust, nil) {
            return .systemTrusted
        }
        let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        let presented = leaf.flatMap(CertificateFingerprint.init(certificate:))
        if let presented, let pin = try? pins.pin(for: host), pin == presented.publicKeySHA256 {
            return .pinned
        }
        if let presented {
            rejected.withLock { $0[host.lowercased()] = presented }
        }
        Self.logger.error("Refused an untrusted certificate from \(host, privacy: .private)")
        return .rejected(presented)
    }
}
