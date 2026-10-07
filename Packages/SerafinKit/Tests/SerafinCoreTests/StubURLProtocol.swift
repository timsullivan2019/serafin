import Foundation
import Synchronization

/// Answers requests from canned responses keyed by host and port, and optionally by path, so connection and
/// sign-in code can be tested offline. Each test uses its own hosts, so tests can run in parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
        /// Never answers, until the request is cancelled.
        case hang
    }

    /// A request the stub received, with its body read out of the stream URLSession hands to protocols.
    struct Received: Sendable {
        let request: URLRequest
        let body: Data

        /// The `Authorization` header.
        var authorization: String? { request.value(forHTTPHeaderField: "Authorization") }
    }

    private static let replies = Mutex<[String: [Reply]]>([:])
    private static let received = Mutex<[String: [Received]]>([:])

    /// Sets what requests to `host:port`, or to one `path` on it, get back. The replies are used in order and the
    /// last one repeats. A stub for a path wins over one for the whole host.
    static func stub(_ hostAndPort: String, path: String? = nil, _ replies: Reply...) {
        stubSequence(hostAndPort, path: path, replies)
    }

    /// ``stub(_:path:_:)`` with the replies in an array.
    static func stubSequence(_ hostAndPort: String, path: String? = nil, _ replies: [Reply]) {
        let key = path.map { hostAndPort + $0 } ?? hostAndPort
        self.replies.withLock { $0[key] = replies }
    }

    /// Every request sent to `path` on `host:port`, oldest first.
    static func requests(to hostAndPort: String, path: String) -> [Received] {
        received.withLock { $0[hostAndPort + path] ?? [] }
    }

    /// The last request sent to `host:port`, on any path.
    static func lastRequest(to hostAndPort: String) -> URLRequest? {
        received.withLock { $0[hostAndPort]?.last?.request }
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
        let hostAndPort = "\(host):\(url.port ?? (url.scheme == "https" ? 443 : 80))"
        let pathKey = hostAndPort + url.path()
        let received = Received(request: request, body: Self.body(of: request))
        Self.received.withLock {
            $0[hostAndPort, default: []].append(received)
            $0[pathKey, default: []].append(received)
        }
        let reply = Self.replies.withLock { replies in
            let key = replies[pathKey] != nil ? pathKey : hostAndPort
            guard var queue = replies[key], let first = queue.first else { return Reply?.none }
            if queue.count > 1 {
                queue.removeFirst()
                replies[key] = queue
            }
            return first
        }
        switch reply {
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

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
