import Foundation
import Testing

@testable import SerafinCore

@Suite struct ServerAddressTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let input: String
        let url: String
        let fallback: String?
        var testDescription: String { input }
    }

    static let valid: [Case] = [
        Case(
            input: "jellyfin.example.com", url: "https://jellyfin.example.com",
            fallback: "https://jellyfin.example.com:8920"),
        Case(
            input: "  Jellyfin.Example.COM  ", url: "https://jellyfin.example.com",
            fallback: "https://jellyfin.example.com:8920"),
        Case(input: "192.168.1.20", url: "http://192.168.1.20:8096", fallback: nil),
        Case(input: "192.168.1.20:8920", url: "https://192.168.1.20:8920", fallback: nil),
        Case(input: "10.0.0.5:8080", url: "http://10.0.0.5:8080", fallback: nil),
        Case(input: "jellyfin.local", url: "http://jellyfin.local:8096", fallback: nil),
        Case(input: "nas", url: "http://nas:8096", fallback: nil),
        Case(input: "example.com:8096", url: "http://example.com:8096", fallback: nil),
        Case(input: "example.com:443", url: "https://example.com:443", fallback: nil),
        Case(
            input: "https://example.com/jellyfin/", url: "https://example.com/jellyfin",
            fallback: "https://example.com:8920/jellyfin"),
        Case(input: "HTTPS://Example.com", url: "https://example.com", fallback: "https://example.com:8920"),
        Case(input: "http://example.com", url: "http://example.com", fallback: "http://example.com:8096"),
        Case(input: "http://192.168.1.20:8096", url: "http://192.168.1.20:8096", fallback: nil),
        Case(input: "[fe80::1]:8096", url: "http://[fe80::1]:8096", fallback: nil),
        Case(input: "::1", url: "http://[::1]:8096", fallback: nil),
        Case(input: "[2001:db8::7]", url: "https://[2001:db8::7]", fallback: "https://[2001:db8::7]:8920"),
    ]

    @Test(arguments: valid)
    func parses(_ testCase: Case) throws {
        let address = try ServerAddress.parse(testCase.input)
        #expect(address.url.absoluteString == testCase.url)
        #expect(address.fallback?.absoluteString == testCase.fallback)
    }

    static let invalid = [
        "", "   ", "exa mple.com", "ftp://example.com", "file:///etc/passwd", "javascript:alert(1)", "mailto:a@b.c",
        "https://", "https://user:secret@example.com", "https://example.com/?api_key=1", "https://example.com/#top",
        "example.com:port",
    ]

    @Test(arguments: invalid)
    func refuses(_ input: String) {
        #expect(throws: SerafinError.invalidAddress) { try ServerAddress.parse(input) }
    }
}

@Suite struct PrivateNetworkTests {
    @Test(
        arguments: [
            "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.0.10", "127.0.0.1", "169.254.10.20", "localhost",
            "media.localhost", "jellyfin.local", "JELLYFIN.LOCAL.", "nas", "::1", "[::1]", "fe80::1", "fe80::1%en0",
            "fd12:3456::1", "::ffff:192.168.1.1",
        ]
    )
    func privateHosts(_ host: String) {
        #expect(PrivateNetwork.isPrivate(host: host))
    }

    @Test(
        arguments: [
            "8.8.8.8", "172.15.0.1", "172.32.0.1", "192.169.0.1", "100.64.0.1", "jellyfin.example.com", "nas.lan",
            "2001:db8::1", "::ffff:8.8.8.8", "",
        ]
    )
    func publicHosts(_ host: String) {
        #expect(!PrivateNetwork.isPrivate(host: host))
    }
}

@Suite struct TransportPolicyTests {
    @Test func httpsIsEncrypted() throws {
        #expect(try TransportPolicy.security(of: #require(URL(string: "https://example.com"))) == .encrypted)
    }

    @Test func plainHTTPIsAllowedOnlyOnAPrivateNetwork() throws {
        let home = try #require(URL(string: "http://192.168.1.20:8096"))
        #expect(try TransportPolicy.security(of: home) == .unencryptedOnPrivateNetwork)
        let internet = try #require(URL(string: "http://example.com"))
        #expect(throws: SerafinError.insecureTransport) { try TransportPolicy.security(of: internet) }
    }

    @Test func otherSchemesAreRefused() throws {
        #expect(throws: SerafinError.invalidAddress) {
            try TransportPolicy.security(of: #require(URL(string: "file:///etc/passwd")))
        }
    }
}
