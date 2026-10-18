import Foundation
import JellyfinAPI
import SerafinCore
import os

/// Sends the server the changes to playback made with an account's downloads, once it can be reached, and has each
/// download take on what the server has.
///
/// Where playback of a download stops, and a download marked watched or not, waits in ``Downloads`` until the server
/// answers. Each change is sent with `POST /UserItems/{itemId}/UserData`, which sets where the item resumes, whether
/// it's watched and when it was last played, as they are, unless the server has a newer change: the item played there
/// after the change was made, as on another device, by the date the server keeps of when it was last played. The
/// server's change wins, and the device's is dropped. So is a change the server turns down for good, as for an item it
/// no longer has. One it can't take now waits, with the rest, for the next pass. Then each download takes on what the
/// server has, unless a change made with it is still waiting, so it resumes offline where the server says.
///
/// One pass runs at a time. Asked again while one runs, it runs once more after it, for changes made meanwhile.
public actor PlaybackSync {
    /// The most items asked about in one request, which keeps its address well inside what servers and the proxies in
    /// front of them accept.
    static let batchSize = 50

    private static let logger = Logger(serafinCategory: "downloads")

    private let client: JellyfinClient
    private let key: SessionKey
    private let downloads: Downloads
    /// The pass running, if there is one.
    private var running: Task<Bool, Never>?
    /// Whether another pass is wanted once the one running ends.
    private var isDue = false
    /// Changes sent or dropped that couldn't be forgotten, as with the device out of space, so they aren't sent again
    /// while they wait to be.
    private var settled: Set<PlaybackChange> = []

    /// Creates the sync of the account `key`'s downloads.
    ///
    /// - Parameters:
    ///   - client: The account's client.
    ///   - key: The account.
    ///   - downloads: Where the account's downloads, and the changes to their playback waiting for the server, are
    ///     kept.
    public init(client: JellyfinClient, key: SessionKey, downloads: Downloads) {
        self.client = client
        self.key = key
        self.downloads = downloads
    }

    /// Sends the changes waiting for the server, then has each download take on what the server has, or does nothing
    /// while the server can't be reached. Returns whether the server took any change, after which screens showing the
    /// server's progress should load again.
    @discardableResult
    public func run() async -> Bool {
        if let running {
            isDue = true
            return await running.value
        }
        let passes = Task {
            var sent = false
            repeat {
                isDue = false
                if await pass() {
                    sent = true
                }
            } while isDue
            running = nil
            return sent
        }
        running = passes
        return await passes.value
    }

    /// One pass. Returns whether the server took any change.
    private func pass() async -> Bool {
        let changes: [PlaybackChange]
        let records: [DownloadRecord]
        do {
            changes = try await downloads.playbackChanges(for: key)
            records = try await downloads.records(for: key)
        } catch {
            Self.logger.error(
                "Could not read the downloads' progress: \(error.localizedDescription, privacy: .private)")
            return false
        }
        // The IDs come from this device's own list, but they go into a request, so they're checked anyway.
        let ids = Set(changes.map(\.itemID) + records.map(\.itemID)).filter(ItemID.isPlain).sorted()
        guard !ids.isEmpty else { return false }
        let items: [String: BaseItemDto]
        do {
            items = try await self.items(ids)
        } catch {
            Self.logger.debug(
                "Could not ask about the downloads' progress: \(error.localizedDescription, privacy: .private)")
            return false
        }
        var sent: Set<String> = []
        for change in changes {
            if settled.contains(change) {
                await forget(change)
                continue
            }
            guard ItemID.isPlain(change.itemID), let item = items[change.itemID] else {
                // The server no longer has the item, or not for this account.
                await forget(change)
                continue
            }
            if let played = item.userData?.lastPlayedDate, played > change.changed {
                // Played on the server since, as on another device, which wins.
                await forget(change)
                continue
            }
            do {
                try await send(change)
                sent.insert(change.itemID)
                await forget(change)
            } catch let error where Self.isTurnedDown(error) {
                await forget(change)
            } catch {
                // The server can't take it now. It waits, with the rest, for the next pass.
                Self.logger.debug(
                    "Could not send a download's progress: \(error.localizedDescription, privacy: .private)")
                break
            }
        }
        // A download whose change was just sent already shows what the server now has.
        for record in records where !sent.contains(record.itemID) {
            guard let userData = items[record.itemID]?.userData else { continue }
            do {
                try await downloads.keepServerPlayback(DownloadPlayback(userData), forItem: record.itemID, key: key)
            } catch {
                Self.logger.error(
                    "Could not keep a download's progress: \(error.localizedDescription, privacy: .private)")
            }
        }
        return !sent.isEmpty
    }

    /// The items among `ids` the server still has for the account, with the account's data for each, by ID, asked for
    /// a few at a time.
    private func items(_ ids: [String]) async throws -> [String: BaseItemDto] {
        var found: [String: BaseItemDto] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            var parameters = Paths.GetItemsParameters(userID: key.userID)
            parameters.ids = Array(ids[start..<min(start + Self.batchSize, ids.count)])
            parameters.enableUserData = true
            parameters.enableImages = false
            parameters.enableTotalRecordCount = false
            let page = try await client.send(Paths.getItems(parameters: parameters)).value
            for item in page.items ?? [] {
                if let id = item.id {
                    found[id] = item
                }
            }
        }
        return found
    }

    /// Sends `change` to the server, which keeps where the item resumes, whether it's watched and when it changed as
    /// they are. The play count stays as it is, since Jellyfin counts a play when it starts, which the server didn't
    /// hear.
    private func send(_ change: PlaybackChange) async throws {
        let userData = UpdateUserItemDataDto(
            isPlayed: change.isPlayed,
            lastPlayedDate: change.changed,
            playbackPositionTicks: Ticks.from(change.position)
        )
        _ = try await client.data(for: Paths.updateItemUserData(itemID: change.itemID, userID: key.userID, userData))
    }

    /// Forgets `change`, unless the item has changed again since.
    private func forget(_ change: PlaybackChange) async {
        do {
            try await downloads.removeChange(change)
            settled.remove(change)
        } catch {
            settled.insert(change)
            Self.logger.error(
                "Could not forget a download's progress: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Whether the server turned a change down for good, so sending it again would be turned down too: a request it
    /// can't read, an account it won't let change the item, or an item it doesn't have.
    static func isTurnedDown(_ error: any Error) -> Bool {
        guard case .unexpectedResponse(let status?)? = SerafinError.translating(error) as? SerafinError else {
            return false
        }
        return [400, 403, 404].contains(status)
    }
}

extension DownloadPlayback {
    /// Where the server says playback of an item stopped, and whether it's been watched, from the account's data for
    /// the item, or nil when the server says it hasn't been started. It's dated when the server says the item was last
    /// played, so a later change made with the download wins.
    public init?(_ userData: UserItemDataDto) {
        let ticks = userData.playbackPositionTicks ?? 0
        let isPlayed = userData.isPlayed ?? false
        guard ticks > 0 || isPlayed || userData.lastPlayedDate != nil else { return nil }
        self.init(
            position: Ticks.duration(ticks), changed: userData.lastPlayedDate ?? .distantPast, isPlayed: isPlayed)
    }
}
