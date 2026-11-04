import Foundation

/// Picks the address a server answers best at on the network the device is on.
///
/// Every address is asked for the server's public info at once, and only an answer with the server's own ID counts,
/// so another server at a home address on someone else's network never wins. The addresses are ranked by kind: on
/// Wi-Fi or a wired network, home addresses first, then Tailscale, then remote ones; on cellular, remote first, then
/// Tailscale, then home. Within a kind the address in use comes first, so two that answer alike don't trade places.
///
/// The best-ranked address that answers wins, but one that hasn't answered yet only holds off a lower-ranked one that
/// has for ``headStart``. Away from home, a home address that never answers costs that much at most, and a remote
/// address that answers slowly on a poor connection still wins once nothing better has.
public struct AddressResolver: Sendable {
    /// Asks an address which server answers there, and returns that server's ID, or throws when none does.
    public typealias Probe = @Sendable (URL) async throws -> String

    /// How long a better-ranked address that hasn't answered holds off a lower-ranked one that has.
    public static let headStart = Duration.seconds(2)
    /// How long an address may sit silent before it counts as not answering.
    public static let timeout: TimeInterval = 10

    private let probe: Probe
    private let headStart: Duration

    /// Creates a resolver.
    ///
    /// - Parameters:
    ///   - headStart: How long a better-ranked address that hasn't answered holds off a lower-ranked one that has.
    ///   - probe: Asks an address which server answers there. Accounts pass one that fetches the public info with
    ///     the user's certificate pins.
    public init(headStart: Duration = AddressResolver.headStart, probe: @escaping Probe) {
        self.headStart = headStart
        self.probe = probe
    }

    /// `server`'s addresses in the order they rank on a network where home addresses come first, as on Wi-Fi, or not,
    /// as on cellular.
    public static func ranking(of server: Server, prefersLocal: Bool) -> [URL] {
        let kinds: [ServerAddressKind] = prefersLocal ? [.local, .tailscale, .remote] : [.remote, .tailscale, .local]
        return kinds.flatMap { kind in
            let ofKind = server.addresses.filter { ServerAddressKind($0) == kind }
            return ofKind.filter { $0 == server.url } + ofKind.filter { $0 != server.url }
        }
    }

    /// The address `server` answers best at, or nil when none of its addresses answers as that server.
    ///
    /// - Parameter prefersLocal: Whether home addresses rank first, as on Wi-Fi or a wired network, rather than remote
    ///   ones, as on cellular.
    public func bestAddress(of server: Server, prefersLocal: Bool) async -> URL? {
        let ranking = Self.ranking(of: server, prefersLocal: prefersLocal)
        guard !ranking.isEmpty else { return nil }
        let id = server.id
        return await withTaskGroup(of: Event.self, returning: URL?.self) { [probe, headStart] group in
            for (rank, address) in ranking.enumerated() {
                group.addTask {
                    .answer(rank: rank, isServer: (try? await probe(address)) == id)
                }
            }
            group.addTask {
                try? await Task.sleep(for: headStart)
                return .headStartOver
            }
            var answers = [Answer](repeating: .waiting, count: ranking.count)
            var isHeadStartOver = false
            while let event = await group.next() {
                switch event {
                case .answer(let rank, let isServer):
                    answers[rank] = isServer ? .server : .none
                case .headStartOver:
                    isHeadStartOver = true
                }
                if let winner = Self.winner(of: answers, isHeadStartOver: isHeadStartOver) {
                    group.cancelAll()
                    return ranking[winner]
                }
                if !answers.contains(.waiting) {
                    group.cancelAll()
                    return nil
                }
            }
            return nil
        }
    }

    /// Which of `server`'s addresses answer as that server, all asked at once, as Settings' Test does.
    public func answeringAddresses(of server: Server) async -> Set<URL> {
        let id = server.id
        return await withTaskGroup(of: URL?.self, returning: Set<URL>.self) { [probe] group in
            for address in server.addresses {
                group.addTask { (try? await probe(address)) == id ? address : nil }
            }
            var answering: Set<URL> = []
            for await address in group {
                if let address {
                    answering.insert(address)
                }
            }
            return answering
        }
    }

    /// The rank of the address that wins with `answers` so far, or nil while it's too early to say: the best-ranked
    /// address still in the running when it has answered, or once the head start is over, the best-ranked one that
    /// has.
    static func winner(of answers: [Answer], isHeadStartOver: Bool) -> Int? {
        guard let best = answers.firstIndex(where: { $0 != .none }) else { return nil }
        if answers[best] == .server {
            return best
        }
        return isHeadStartOver ? answers.firstIndex(of: .server) : nil
    }

    /// What one address has said so far.
    enum Answer: Equatable {
        /// Nothing yet.
        case waiting
        /// It answered as the server.
        case server
        /// Nothing answered, or another server did.
        case none
    }

    private enum Event: Sendable {
        case answer(rank: Int, isServer: Bool)
        case headStartOver
    }
}
