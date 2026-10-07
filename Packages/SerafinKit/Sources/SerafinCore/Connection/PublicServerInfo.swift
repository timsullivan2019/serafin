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
