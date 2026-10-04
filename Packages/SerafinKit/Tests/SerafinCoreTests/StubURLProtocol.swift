import Foundation
import Synchronization

/// Answers requests from canned responses keyed by host and port, so connection code can be tested offline.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
        /// Never answers, until the request is cancelled.
        case hang
    }

    private static let replies = Mutex<[String: Reply]>([:])
    private static let requests = Mutex<[String: URLRequest]>([:])

    /// Sets what requests to `host:port` get back. Each test uses its own hosts, so tests can run in parallel.
    static func stub(_ hostAndPort: String, _ reply: Reply) {
        replies.withLock { $0[hostAndPort] = reply }
    }

    /// The last request sent to `host:port`.
    static func lastRequest(to hostAndPort: String) -> URLRequest? {
        requests.withLock { $0[hostAndPort] }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let key = "\(host):\(url.port ?? (url.scheme == "https" ? 443 : 80))"
        Self.requests.withLock { $0[key] = request }
        switch Self.replies.withLock({ $0[key] }) {
        case .json(let status, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .hang:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

    override func stopLoading() {}
}
