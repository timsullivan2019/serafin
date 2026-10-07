import Foundation
import os

/// The servers the user has added, saved as JSON under Application Support.
///
/// The file is written atomically with complete file protection, so it is unreadable while the device is
/// locked. It never contains tokens or pins. Its format is versioned so later releases can migrate it:
///
/// ```json
/// {
///   "version": 1,
///   "servers": [
///     { "id": "…", "name": "…", "url": "https://…", "lastUserID": "…", "users": [ { "id": "…", "name": "…" } ] }
///   ]
/// }
/// ```
public actor ServerStore {
    private struct File: Codable {
        var version: Int
        var servers: [Server]
    }

    private static let currentVersion = 1
    private static let logger = Logger(serafinCategory: "servers")

    private let fileURL: URL
    private var cached: [Server]?

    /// Creates a store.
    ///
    /// - Parameter fileURL: Where the list is saved. Defaults to `Serafin/servers.json` in Application Support.
    public init(fileURL: URL = ServerStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// The default location of the server list.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Serafin/servers.json", directoryHint: .notDirectory)
    }

    /// Every saved server, in the order they were added.
    public func servers() throws -> [Server] {
        if let cached { return cached }
        let loaded = try load()
        cached = loaded
        return loaded
    }

    /// The saved server with `id`, if there is one.
    public func server(id: String) throws -> Server? {
        try servers().first { $0.id == id }
    }

    /// Saves `server`, replacing a saved server with the same ID or adding it at the end.
    public func save(_ server: Server) throws {
        var list = try servers()
        if let index = list.firstIndex(where: { $0.id == server.id }) {
            list[index] = server
        } else {
            list.append(server)
        }
        try write(list)
    }

    /// Removes the server with `id`. Removing a server that is not saved is not an error.
    public func remove(id: String) throws {
        try write(try servers().filter { $0.id != id })
    }

    /// Renames the server with `serverID`, when the server reports a new name. Renaming a server that is not saved
    /// does nothing.
    public func setName(_ name: String, forServer serverID: String) throws {
        guard var server = try server(id: serverID), server.name != name else { return }
        server.name = name
        try save(server)
    }

    /// Records which user signed in to a server most recently.
    public func setLastUser(_ userID: String?, forServer serverID: String) throws {
        guard var server = try server(id: serverID) else { return }
        server.lastUserID = userID
        try save(server)
    }

    private func load() throws -> [Server] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return [] }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: fileURL))
            return file.servers
        } catch {
            Self.logger.error("Could not read the server list: \(error.localizedDescription, privacy: .private)")
            throw SerafinError.serverStoreUnavailable
        }
    }

    private func write(_ list: [Server]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(File(version: Self.currentVersion, servers: list))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            cached = list
        } catch {
            Self.logger.error("Could not save the server list: \(error.localizedDescription, privacy: .private)")
            throw SerafinError.serverStoreUnavailable
        }
    }
}
