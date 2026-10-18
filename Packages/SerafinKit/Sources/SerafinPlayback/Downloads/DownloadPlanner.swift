import Foundation
import JellyfinAPI
import SerafinCore

/// How an item can be downloaded, as the server answers for Serafin's device profile.
public enum DownloadPlan: Sendable, Equatable {
    /// The original file plays on this device as it is, so it's saved as it is.
    case original(OriginalDownload)
    /// The player can't open the original file. Saving it needs the server to make a copy the player can open.
    case needsConversion
}

/// An original file to save.
public struct OriginalDownload: Sendable, Equatable {
    /// The server's ID for the version, which is also the item ID Jellyfin downloads it by.
    public let mediaSourceID: String
    /// The file's address, without the token, which goes in the `Authorization` header.
    public let url: URL
    /// The extension to save it with, one the player opens.
    public let fileExtension: String
    /// The file's size in bytes, when the server said.
    public let bytes: Int64?
}

/// Asks the server whether an item's original file plays on this device, and where to download it.
///
/// It asks for the item's playback info as the player does, with Serafin's device profile, but with direct play
/// alone allowed and no bitrate cap, since a download isn't streamed. When the server says the original direct plays,
/// it's downloaded from `GET /Items/{id}/Download`, which applies the server's download permission and supports
/// ranges, so a stopped transfer can carry on.
public struct DownloadPlanner: Sendable {
    /// The bitrate the profile allows for a download: 1 Gbps, so no file is turned away for its bitrate.
    static let bitrate = 1_000_000_000

    private let client: JellyfinClient
    private let userID: String
    private let video: VideoSupport?

    /// Creates a planner.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    ///   - video: The AV1 and Dolby Vision the device plays, or nil to read it from the device.
    public init(client: JellyfinClient, userID: String, video: VideoSupport? = nil) {
        self.client = client
        self.userID = userID
        self.video = video
        if video == nil {
            VideoSupport.prepare()
        }
    }

    /// How `itemID` can be downloaded.
    ///
    /// - Parameter mediaSourceID: The version to download, or nil for the server's first.
    /// - Throws: A ``PlaybackError`` when the server refuses, or SerafinCore's `SerafinError` when it can't be reached
    ///   or no longer accepts the sign-in.
    public func plan(for itemID: String, mediaSourceID: String? = nil) async throws -> DownloadPlan {
        let body = PlaybackInfoDto(
            deviceProfile: .serafin(maxBitrate: Self.bitrate, video: video ?? .current),
            enableDirectPlay: true,
            enableDirectStream: false,
            enableTranscoding: false,
            isAutoOpenLiveStream: false,
            maxStreamingBitrate: Self.bitrate,
            mediaSourceID: mediaSourceID,
            userID: userID
        )
        let response: PlaybackInfoResponse
        do {
            response = try await client.send(Paths.getPostedPlaybackInfo(itemID: itemID, body)).value
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        return try Self.plan(from: response, itemID: itemID, mediaSourceID: mediaSourceID, client: client)
    }

    /// Reads the server's answer: the original when the chosen version is a file on the server that direct plays.
    static func plan(
        from response: PlaybackInfoResponse,
        itemID: String,
        mediaSourceID: String?,
        client: JellyfinClient
    ) throws -> DownloadPlan {
        let sources = response.mediaSources ?? []
        let source = sources.first { $0.id == mediaSourceID } ?? sources.first
        switch response.errorCode {
        case nil, .noCompatibleStream:
            break
        case let code?:
            throw PlaybackError(code)
        }
        guard let source else {
            if response.errorCode == .noCompatibleStream { return .needsConversion }
            throw PlaybackError.notPlayable
        }
        guard
            response.errorCode == nil,
            source.isSupportsDirectPlay == true,
            source.`protocol` == .file,
            source.isRemote != true,
            let fileExtension = fileExtension(for: source)
        else {
            return .needsConversion
        }
        let id = source.id ?? itemID
        guard ItemID.isPlain(id), let url = client.url(with: Paths.getDownload(itemID: id)) else {
            throw PlaybackError.notPlayable
        }
        return .original(
            OriginalDownload(
                mediaSourceID: id,
                url: url,
                fileExtension: fileExtension,
                bytes: source.size.map(Int64.init)
            )
        )
    }

    /// The extension to save `source` with: its file's own when the player opens that, otherwise the first container
    /// the server lists that the player opens. Jellyfin lists an MP4's container as `mov,mp4,m4a,3gp,3g2,mj2`.
    static func fileExtension(for source: MediaSourceInfo) -> String? {
        let playable = Downloads.playableExtensions
        if let path = source.path {
            let ext = URL(filePath: path).pathExtension.lowercased()
            if playable.contains(ext) { return ext }
        }
        let containers = (source.container ?? "").lowercased().split(separator: ",").map(String.init)
        if containers.contains("mp4") { return "mp4" }
        return containers.first { playable.contains($0) }
    }
}
