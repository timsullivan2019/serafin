import Foundation
import JellyfinAPI

/// What an unauthenticated server reports about itself, checked to be a supported Jellyfin server.
public struct PublicServerInfo: Equatable, Sendable {
    /// The oldest Jellyfin release Serafin supports.
    public static let minimumVersion = "10.10.0"

    /// The server's own ID.
    public let id: String
    /// The server's name.
    public let name: String
    /// The server's version, such as "10.10.7".
    public let version: String
    /// The address the server gives for itself on its own network, such as `http://192.168.1.20:8096`, or nil when it
    /// gives none Serafin can use. It's only a lead: a server in a container often gives an address that only the
    /// container can reach, so Serafin offers it only once the server has answered there.
    public let localAddress: URL?

    /// The longest local address Serafin reads. A real one is a few dozen characters.
    static let maximumAddressLength = 512

    /// Checks the public system info a server returned.
    ///
    /// - Throws: ``SerafinError/notJellyfin`` when it is not a Jellyfin server or leaves out its ID or version,
    ///   and ``SerafinError/unsupportedServerVersion(_:)`` when it is older than ``minimumVersion``.
    public init(validating info: PublicSystemInfo) throws {
        guard
            info.productName?.localizedCaseInsensitiveContains("jellyfin") == true,
            let id = info.id, !id.isEmpty,
            let version = info.version, !version.isEmpty
        else { throw SerafinError.notJellyfin }
        guard Self.isSupported(version) else { throw SerafinError.unsupportedServerVersion(version) }
        self.id = id
        self.name = info.serverName.flatMap { $0.isEmpty ? nil : $0 } ?? "Jellyfin"
        self.version = version
        self.localAddress = Self.address(info.localAddress)
    }

    /// The address in `text`, checked as an address the user typed would be, or nil when it isn't a usable one.
    static func address(_ text: String?) -> URL? {
        guard let text, text.utf8.count <= maximumAddressLength, text.contains("://") else { return nil }
        return try? ServerAddress.parse(text).url
    }

    /// Whether `version` is at least ``minimumVersion``, comparing numeric parts.
    static func isSupported(_ version: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            text.split(separator: ".").prefix(3).map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let have = parts(version) + Array(repeating: 0, count: 3)
        let need = parts(minimumVersion)
        for index in need.indices where have[index] != need[index] {
            return have[index] > need[index]
        }
        return true
    }
}
