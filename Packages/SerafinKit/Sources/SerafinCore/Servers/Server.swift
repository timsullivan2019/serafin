import Foundation
import Network

/// A Jellyfin server the user has added. It holds no secrets: tokens and certificate pins live in the
/// ``SecretStore``.
///
/// A server can have several addresses, such as one at home and one for anywhere else. It's one server whichever
/// answers, since a server is known by the ID it reports, so its users stay signed in at all of them.
public struct Server: Codable, Hashable, Identifiable, Sendable {
    /// The most addresses Serafin keeps for a server.
    public static let maximumAddresses = 4

    /// The server's own ID, from its public system info. It stays the same if the server moves address.
    public var id: String
    /// The name the server reports, shown in Serafin's server list.
    public var name: String
    /// The address Serafin connects to now, one of ``addresses``. Serafin moves it to whichever of them answers best
    /// on the network the device is on.
    public private(set) var url: URL
    /// Every address the server answers at, in the order they were added. It always holds ``url``, and never more
    /// than ``maximumAddresses``.
    public private(set) var addresses: [URL]
    /// The user who was signed in most recently, so switching servers lands on the right account.
    public var lastUserID: String?
    /// The users signed in to this server on this device, in the order they signed in.
    public var users: [ServerUser]

    /// Creates a server.
    ///
    /// - Parameters:
    ///   - id: The server's own ID.
    ///   - name: The name the server reports.
    ///   - url: The address Serafin connects to.
    ///   - addresses: Every address the server answers at. `url` is added when it's not among them, and only the first
    ///     ``maximumAddresses`` are kept.
    ///   - lastUserID: The user signed in most recently, if any.
    ///   - users: The users signed in to this server.
    public init(
        id: String, name: String, url: URL, addresses: [URL] = [], lastUserID: String? = nil,
        users: [ServerUser] = []
    ) {
        var kept: [URL] = []
        for address in addresses where !kept.contains(where: { Self.isSame($0, address) }) {
            kept.append(address)
        }
        let current: URL
        if let index = kept.firstIndex(where: { Self.isSame($0, url) }) {
            current = kept[index]
        } else {
            current = url
            kept.insert(url, at: 0)
        }
        if kept.count > Self.maximumAddresses {
            let others = kept.filter { $0 != current }.prefix(Self.maximumAddresses - 1)
            kept = kept.filter { $0 == current || others.contains($0) }
        }
        self.id = id
        self.name = name
        self.url = current
        self.addresses = kept
        self.lastUserID = lastUserID
        self.users = users
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, url, addresses, lastUserID, users
    }

    /// Reads a saved server. A server saved before Serafin kept several addresses has only the one it connected to.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            url: try container.decode(URL.self, forKey: .url),
            addresses: try container.decodeIfPresent([URL].self, forKey: .addresses) ?? [],
            lastUserID: try container.decodeIfPresent(String.self, forKey: .lastUserID),
            users: try container.decode([ServerUser].self, forKey: .users)
        )
    }

    /// The signed-in user with `id`, if there is one.
    public func user(id: String) -> ServerUser? {
        users.first { $0.id == id }
    }

    /// The name to show for the server: the name it reports, unless that is a generated one, when it's the host name
    /// of one of its addresses, the same whichever is in use. See ``ServerName``.
    public var displayName: String {
        ServerName.display(name, at: addresses)
    }

    /// The saved address that is the same as `address`, if there is one.
    public func address(matching address: URL) -> URL? {
        addresses.first { Self.isSame($0, address) }
    }

    /// The address to put in a link for someone else to open: the first remote one, since an address at home works
    /// only there, or the address in use when the server has no remote one.
    public var sharingAddress: URL {
        addresses.first { ServerAddressKind($0) == .remote } ?? url
    }

    /// Adds `address` after the others, unless the server has it already.
    ///
    /// - Throws: ``SerafinError/tooManyAddresses`` when the server has ``maximumAddresses`` already.
    public mutating func add(_ address: URL) throws {
        guard self.address(matching: address) == nil else { return }
        guard addresses.count < Self.maximumAddresses else { throw SerafinError.tooManyAddresses }
        addresses.append(address)
    }

    /// Connects at `address` from now on, when it's one of the server's addresses.
    ///
    /// - Returns: Whether `address` is one of them.
    @discardableResult
    public mutating func use(_ address: URL) -> Bool {
        guard let saved = self.address(matching: address) else { return false }
        url = saved
        return true
    }

    /// Forgets `address`. When it was the one in use, the first address left takes its place. The last address stays,
    /// since a server can't have none.
    ///
    /// - Returns: Whether `address` was forgotten.
    @discardableResult
    public mutating func remove(_ address: URL) -> Bool {
        guard addresses.count > 1, let saved = self.address(matching: address) else { return false }
        addresses.removeAll { $0 == saved }
        if url == saved, let first = addresses.first {
            url = first
        }
        return true
    }

    /// Whether `a` and `b` are the same address: the same scheme, host and port, with the scheme's own port written or
    /// not, and the same path, with or without a slash at the end.
    static func isSame(_ a: URL, _ b: URL) -> Bool {
        func parts(_ url: URL) -> (scheme: String, host: String, port: Int?, path: String) {
            let scheme = url.scheme?.lowercased() ?? ""
            let defaultPort = scheme == "https" ? 443 : scheme == "http" ? 80 : nil
            var path = url.path(percentEncoded: true)
            while path.hasSuffix("/") {
                path.removeLast()
            }
            return (scheme, url.host(percentEncoded: false)?.lowercased() ?? "", url.port ?? defaultPort, path)
        }
        return parts(a) == parts(b)
    }
}

/// Where one of a server's addresses reaches it, which decides when Serafin tries it.
public enum ServerAddressKind: Hashable, Sendable {
    /// The user's own network, such as `192.168.1.20` or `nas.local`, which answers at home.
    case local
    /// The user's tailnet, such as `100.101.102.103` or `nas.tailnet-1234.ts.net`, which answers wherever Tailscale
    /// is on.
    case tailscale
    /// The internet, such as `jellyfin.example.com`, which answers anywhere.
    case remote

    /// The kind of `address`, judged from its host alone. Nothing is resolved, so a public name that points at a
    /// home server counts as remote.
    public init(_ address: URL) {
        let host = address.host(percentEncoded: false) ?? ""
        if PrivateNetwork.isTailscale(host: host) {
            self = .tailscale
        } else if PrivateNetwork.isPrivate(host: host) {
            self = .local
        } else {
            self = .remote
        }
    }
}

/// How Serafin names a server on screen.
///
/// A server in a Docker container that nobody has named reports the container's ID as its name, twelve hex digits
/// such as `3f9a1c07be52`, which reads like an error. Serafin shows the address's host name instead, such as `nas`,
/// or "Jellyfin" when the address is an IP address, which says no more.
enum ServerName {
    /// The name to show for a server that reports `name` and is reached at `url`.
    static func display(_ name: String, at url: URL) -> String {
        display(name, at: [url])
    }

    /// The name to show for a server that reports `name` and is reached at `addresses`: the host name of the first
    /// address that has one, when `name` is generated.
    static func display(_ name: String, at addresses: [URL]) -> String {
        guard isGenerated(name) else { return name }
        return addresses.lazy.compactMap(hostName(of:)).first ?? "Jellyfin"
    }

    /// `url`'s host when it's a name rather than an IP address, or nil.
    private static func hostName(of url: URL) -> String? {
        guard let host = url.host(), !host.isEmpty, !host.contains(":"), IPv4Address(host) == nil else { return nil }
        return host
    }

    /// Whether `name` was made by a machine rather than a person: empty, or a container's or server's ID, which is
    /// 12, 32 or 64 hex digits.
    static func isGenerated(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || ([12, 32, 64].contains(name.count) && name.allSatisfy(\.isHexDigit))
    }
}

/// A user signed in to a server. Only the ID and the name are kept, to list accounts without a network request;
/// the user's token lives in the ``SecretStore``.
public struct ServerUser: Codable, Hashable, Identifiable, Sendable {
    /// The user's ID on the server.
    public var id: String
    /// The user's name, as the server reports it.
    public var name: String

    /// Creates a user.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
