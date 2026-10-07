import Foundation
import Security

/// Self-signed P-256 certificates for `jellyfin.local`, made once with `openssl req -x509` for the pinning tests.
/// Their private keys were never kept. A1 and A2 share a key, as a renewal would; B has its own.
enum TestCertificates {
    static let a1 = certificate(
        "MIIBdTCCARygAwIBAgIBATAKBggqhkjOPQQDAjAZMRcwFQYDVQQDDA5qZWxseWZpbi5sb2NhbDAgFw0yNjEwMDQxNjI1MDdaGA8yMTI2MDkxMDE2"
            + "MjUwN1owGTEXMBUGA1UEAwwOamVsbHlmaW4ubG9jYWwwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASwFcg0c5cP2ZZBJ+6jQJ+YEVOYA70zRSni"
            + "YN1bInXP3CAbcePli9EDc+Wz9nL/ZXAB0x+eXRjTu/wpITA0Bk9Uo1MwUTAdBgNVHQ4EFgQURKKl8xfgUAlaVc5Ey4uKpzD76gYwHwYDVR0jBBgw"
            + "FoAURKKl8xfgUAlaVc5Ey4uKpzD76gYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiBop+aInPDjNVWcwDKdylYrOA+H7VHrddf9"
            + "O7QX3vKIoAIgG+PWfaDcYAbouCt2YpIh9Toh1qi/1btQHAMd8oHYl9U="
    )

    static let a2 = certificate(
        "MIIBdzCCARygAwIBAgIBAjAKBggqhkjOPQQDAjAZMRcwFQYDVQQDDA5qZWxseWZpbi5sb2NhbDAgFw0yNjEwMDQxNjI1MDdaGA8yMTI2MDkxMDE2"
            + "MjUwN1owGTEXMBUGA1UEAwwOamVsbHlmaW4ubG9jYWwwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAASwFcg0c5cP2ZZBJ+6jQJ+YEVOYA70zRSni"
            + "YN1bInXP3CAbcePli9EDc+Wz9nL/ZXAB0x+eXRjTu/wpITA0Bk9Uo1MwUTAdBgNVHQ4EFgQURKKl8xfgUAlaVc5Ey4uKpzD76gYwHwYDVR0jBBgw"
            + "FoAURKKl8xfgUAlaVc5Ey4uKpzD76gYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNJADBGAiEAmBqU+aWq6oxUYhMZfm2avLOwGKyAJK/o"
            + "vOwk0LOqiVoCIQCJWoFq7pirvf3QSgPE12lGMNoMWq92ElrnRM/gm3zf9g=="
    )

    static let b = certificate(
        "MIIBdTCCARygAwIBAgIBAzAKBggqhkjOPQQDAjAZMRcwFQYDVQQDDA5qZWxseWZpbi5sb2NhbDAgFw0yNjEwMDQxNjI1MDdaGA8yMTI2MDkxMDE2"
            + "MjUwN1owGTEXMBUGA1UEAwwOamVsbHlmaW4ubG9jYWwwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQfI1FATC1KNL1CRH04hHEqB1fS0pYQqTNU"
            + "MWHepv9R4W5gohDHyeHHCId9yOnGOs3NJGK8K6c5yzGz0WI7pyijo1MwUTAdBgNVHQ4EFgQUZ0Wid9D1lqM0H7AoUrxbUkXrikwwHwYDVR0jBBgw"
            + "FoAUZ0Wid9D1lqM0H7AoUrxbUkXrikwwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNHADBEAiAcLhLm9gV13MrT5vyHS/2SbWKKU4ae/tv4"
            + "kmK7RF2OQQIgCYGlk7e4Focrd1JcAXowKaO03v0ECwkHr7lPl+4qAqQ="
    )

    /// The `openssl x509 -fingerprint -sha256` of A1.
    static let a1CertificateSHA256 =
        "5D:61:7A:3B:CA:4D:67:42:87:8F:FB:4D:45:3F:81:5E:EA:8E:22:9B:53:CB:3D:5E:F1:82:7C:B4:8E:A1:D4:E2"

    /// SHA-256 of key A's uncompressed public point, as `openssl ec -pubout` gives it.
    static let keyASHA256 =
        "5D:65:BE:8A:07:5A:D5:36:36:7F:42:D4:9D:6D:30:E1:7F:88:60:4E:82:26:91:A6:73:E4:F5:9A:C5:CE:AA:51"

    private static func certificate(_ base64: String) -> SecCertificate? {
        Data(base64Encoded: base64).flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    /// A trust object for `certificate` as a TLS server named `host`.
    static func trust(_ certificate: SecCertificate, host: String = "jellyfin.local") -> SecTrust? {
        trust(certificate, policy: SecPolicyCreateSSL(true, host as CFString))
    }

    /// A trust object for `certificate` under `policy`.
    static func trust(_ certificate: SecCertificate, policy: SecPolicy) -> SecTrust? {
        var trust: SecTrust?
        SecTrustCreateWithCertificates(certificate, policy, &trust)
        return trust
    }
}
