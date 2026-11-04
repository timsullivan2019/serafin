import Foundation
import Synchronization

/// Answers requests from canned responses keyed by host and port, and optionally by path and query items, so
/// connection, sign-in and library code can be tested offline. Each test uses its own hosts, so tests can run in
/// parallel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
        /// Never answers, until the request is cancelled.
        case hang
        /// Answers with the reply once ``release(_:)`` is called with this name, so a test can act while the request is
        /// on its way.
        indirect case held(String, Reply)
    }

    /// A request the stub received, with its body read out of the stream URLSession hands to protocols.
    struct Received: Sendable {
        let request: URLRequest
        let body: Data

        /// The `Authorization` header.
        var authorization: String? { request.value(forHTTPHeaderField: "Authorization") }

        /// The value of the query item `name`, if the request has one.
        func query(_ name: String) -> String? {
            queryValues(name).first
        }

        /// Every value of the query item `name`, in order. The SDK repeats a name for each value of a list.
        func queryValues(_ name: String) -> [String] {
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            return (items ?? []).filter { $0.name == name }.compactMap(\.value)
        }
    }

    private struct Stub {
        let hostAndPort: String
        let path: String?
        let query: [String: String]
        var replies: [Reply]

        func matches(hostAndPort: String, path: String, query items: [URLQueryItem]) -> Bool {
            hostAndPort == self.hostAndPort && (self.path == nil || self.path == path)
                && query.allSatisfy { name, value in items.contains { $0.name == name && $0.value == value } }
        }

        /// How specific the stub is, so a stub for a path wins over one for the whole host.
        var specificity: Int { (path == nil ? 0 : 1) + query.count }
    }

    /// A request held until its name is released, with the run loop URLSession started it on, where its answer has
    /// to come from.
    private struct Held: @unchecked Sendable {
        let stub: StubURLProtocol
        let url: URL
        let reply: Reply
        let runLoop: CFRunLoop
    }

    /// The names released so far, and the requests waiting for theirs.
    private struct Holds {
        var released: Set<String> = []
        var waiting: [String: [Held]] = [:]
    }

    private static let stubs = Mutex<[Stub]>([])
    private static let received = Mutex<[String: [Received]]>([:])
    private static let holds = Mutex(Holds())

    /// Sets what requests to `host:port`, or to one `path` on it with the given query items, get back. The replies
    /// are used in order and the last one repeats. The most specific matching stub answers.
    static func stub(_ hostAndPort: String, path: String? = nil, query: [String: String] = [:], _ replies: Reply...) {
        stubSequence(hostAndPort, path: path, query: query, replies)
    }

    /// ``stub(_:path:query:_:)`` with the replies in an array.
    static func stubSequence(
        _ hostAndPort: String,
        path: String? = nil,
        query: [String: String] = [:],
        _ replies: [Reply]
    ) {
        stubs.withLock { stubs in
            stubs.removeAll { $0.hostAndPort == hostAndPort && $0.path == path && $0.query == query }
            stubs.append(Stub(hostAndPort: hostAndPort, path: path, query: query, replies: replies))
        }
    }

    /// Every request sent to `path` on `host:port`, oldest first.
    static func requests(to hostAndPort: String, path: String) -> [Received] {
        received.withLock { $0[hostAndPort + path] ?? [] }
    }

    /// The last request sent to `host:port`, on any path.
    static func lastRequest(to hostAndPort: String) -> URLRequest? {
        received.withLock { $0[hostAndPort]?.last?.request }
    }

    /// Waits until a request to `path` on `host:port` has arrived.
    static func waitForRequest(to hostAndPort: String, path: String) async throws {
        while requests(to: hostAndPort, path: path).isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Answers the requests held under `name`, and any that arrive later.
    static func release(_ name: String) {
        let waiting = holds.withLock { holds -> [Held] in
            holds.released.insert(name)
            return holds.waiting.removeValue(forKey: name) ?? []
        }
        for held in waiting {
            CFRunLoopPerformBlock(held.runLoop, CFRunLoopMode.commonModes.rawValue) {
                held.stub.respond(with: held.reply, to: held.url)
            }
            CFRunLoopWakeUp(held.runLoop)
        }
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
        let path = url.path()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let received = Received(request: request, body: Self.body(of: request))
        Self.received.withLock {
            $0[hostAndPort, default: []].append(received)
            $0[hostAndPort + path, default: []].append(received)
        }
        let reply = Self.stubs.withLock { stubs -> Reply? in
            let matching = stubs.indices.filter {
                stubs[$0].matches(hostAndPort: hostAndPort, path: path, query: items)
            }
            guard let index = matching.max(by: { stubs[$0].specificity < stubs[$1].specificity }),
                let first = stubs[index].replies.first
            else { return nil }
            if stubs[index].replies.count > 1 {
                stubs[index].replies.removeFirst()
            }
            return first
        }
        respond(with: reply, to: url)
    }

    override func stopLoading() {}

    private func respond(with reply: Reply?, to url: URL) {
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
        case .held(let name, let later):
            let held = Held(stub: self, url: url, reply: later, runLoop: CFRunLoopGetCurrent())
            let isReleased = Self.holds.withLock { holds -> Bool in
                guard !holds.released.contains(name) else { return true }
                holds.waiting[name, default: []].append(held)
                return false
            }
            if isReleased {
                respond(with: later, to: url)
            }
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

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
