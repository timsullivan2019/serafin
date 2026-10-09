import Foundation
import Testing

// App Transport Security reads the app's Info.plist, so these run inside the Serafin app as their host. iOS refuses
// a blocked request before sending anything; an allowed one here goes to an address with nothing on it, so the test
// only checks that the failure isn't iOS's refusal.
@Suite struct TransportSecurityTests {
    /// What went wrong loading `address`, or nil if it loaded.
    private func failure(loading address: String) async throws -> URLError.Code? {
        let url = try #require(URL(string: address))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await session.data(from: url)
            return nil
        } catch let error as URLError {
            return error.code
        }
    }

    @Test(arguments: ["http://100.64.0.1:9/", "http://100.127.255.254:9/", "http://nas.tailnet-1234.ts.net:9/"])
    func allowsPlainHTTPOverTailscale(_ address: String) async throws {
        let code = try await failure(loading: address)
        #expect(code != .appTransportSecurityRequiresSecureConnection)
    }

    @Test(
        arguments: [
            "http://100.128.0.1:9/", "http://8.8.8.8:9/", "http://example.com:9/", "http://ts.net.example.com:9/",
        ]
    )
    func blocksPlainHTTPEverywhereElse(_ address: String) async throws {
        let code = try await failure(loading: address)
        #expect(code == .appTransportSecurityRequiresSecureConnection)
    }
}
