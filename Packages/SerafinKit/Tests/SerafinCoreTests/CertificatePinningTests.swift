import Foundation
import Security
import Testing

@testable import SerafinCore

@Suite struct CertificatePinningTests {
    private let secrets = InMemorySecretStore()
    private var pins: PinStore { PinStore(secrets: secrets) }

    private func certificate(_ certificate: SecCertificate?) throws -> SecCertificate {
        try #require(certificate)
    }

    private func fingerprint(_ certificate: SecCertificate?) throws -> CertificateFingerprint {
        let unwrapped = try self.certificate(certificate)
        return try #require(CertificateFingerprint(certificate: unwrapped))
    }

    private func trust(_ certificate: SecCertificate?) throws -> SecTrust {
        let unwrapped = try self.certificate(certificate)
        return try #require(TestCertificates.trust(unwrapped))
    }

    @Test func fingerprintsMatchWhatOpenSSLReports() throws {
        let fingerprint = try fingerprint(TestCertificates.a1)
        #expect(fingerprint.certificateSHA256 == TestCertificates.a1CertificateSHA256)
        #expect(fingerprint.publicKeySHA256 == TestCertificates.keyASHA256)
    }

    @Test func anUnpinnedSelfSignedCertificateIsRefusedAndRememberedUntilTheNextTry() throws {
        let delegate = PinningDelegate(pins: pins)
        let presented = try fingerprint(TestCertificates.a1)
        #expect(delegate.evaluate(try trust(TestCertificates.a1), host: "jellyfin.local") == .rejected(presented))
        #expect(delegate.rejectedCertificate(for: "JELLYFIN.local") == presented)
        delegate.forgetRejection(for: "jellyfin.local")
        #expect(delegate.rejectedCertificate(for: "jellyfin.local") == nil)
    }

    @Test func aPinnedCertificateIsAccepted() throws {
        try pins.setPin(fingerprint(TestCertificates.a1), for: "jellyfin.local")
        #expect(PinningDelegate(pins: pins).evaluate(try trust(TestCertificates.a1), host: "jellyfin.local") == .pinned)
    }

    @Test func aRenewedCertificateWithTheSameKeyIsStillAccepted() throws {
        try pins.setPin(fingerprint(TestCertificates.a1), for: "jellyfin.local")
        #expect(PinningDelegate(pins: pins).evaluate(try trust(TestCertificates.a2), host: "jellyfin.local") == .pinned)
    }

    @Test func aDifferentKeyIsRefusedEvenWithAPin() throws {
        try pins.setPin(fingerprint(TestCertificates.a1), for: "jellyfin.local")
        let decision = PinningDelegate(pins: pins).evaluate(try trust(TestCertificates.b), host: "jellyfin.local")
        #expect(decision == .rejected(try fingerprint(TestCertificates.b)))
    }

    @Test func aPinAppliesOnlyToItsHost() throws {
        try pins.setPin(fingerprint(TestCertificates.a1), for: "other.local")
        let decision = PinningDelegate(pins: pins).evaluate(try trust(TestCertificates.a1), host: "jellyfin.local")
        #expect(decision == .rejected(try fingerprint(TestCertificates.a1)))
    }

    @Test func aCertificateTheSystemTrustsNeedsNoPin() throws {
        // The test certificates are not valid TLS server certificates (no subject alternative name), so this checks
        // the trusted path with a plain X.509 policy and the certificate as its own anchor.
        let anchor = try certificate(TestCertificates.a1)
        let trust = try #require(TestCertificates.trust(anchor, policy: SecPolicyCreateBasicX509()))
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        #expect(PinningDelegate(pins: pins).evaluate(trust, host: "jellyfin.local") == .systemTrusted)
    }

    @Test func pinsCanBeRemoved() throws {
        try pins.setPin(fingerprint(TestCertificates.a1), for: "jellyfin.local")
        #expect(try pins.pin(for: "JELLYFIN.LOCAL") == TestCertificates.keyASHA256)
        try pins.removePin(for: "jellyfin.local")
        #expect(try pins.pin(for: "jellyfin.local") == nil)
    }
}
