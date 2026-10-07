import Foundation
import JellyfinAPI

/// A Jellyfin server that answered a broadcast on the local network.
public struct DiscoveredServer: Hashable, Identifiable, Sendable {
    /// The server's own ID.
    public let id: String
    /// The server's name.
    public let name: String
    /// The address it advertised, already checked against Serafin's transport rules.
    public let url: URL

    /// The name to show for the server, which is its host name when it reports a generated one. See ``ServerName``.
    public var displayName: String {
        ServerName.display(name, at: url)
    }
}

/// Finds Jellyfin servers on the local network with Jellyfin's UDP discovery on port 7359.
///
/// On a device this needs Apple's multicast networking entitlement, which Apple grants on request; the simulator
/// works without it.
public enum LocalDiscovery {
    /// Servers that answer within `duration`, each reported once.
    ///
    /// Every answer is untrusted input: one whose address is not http or https, or is plain HTTP to a public host,
    /// is dropped. Discovery failures end the stream quietly, since the user can always type an address.
    public static func servers(listeningFor duration: Duration = .seconds(3)) -> AsyncStream<DiscoveredServer> {
        AsyncStream { continuation in
            let task = Task {
                var seen = Set<String>()
                do {
                    for try await answer in JellyfinClient.discover(duration: duration) {
                        if let server = accept(id: answer.id, name: answer.name, url: answer.url),
                            seen.insert(server.id).inserted
                        {
                            continuation.yield(server)
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Checks one discovery answer, returning nil when it must be ignored.
    static func accept(id: String, name: String, url: URL) -> DiscoveredServer? {
        guard !id.isEmpty, (try? TransportPolicy.security(of: url)) != nil else { return nil }
        return DiscoveredServer(id: id, name: name.isEmpty ? "Jellyfin" : name, url: url)
    }
}
