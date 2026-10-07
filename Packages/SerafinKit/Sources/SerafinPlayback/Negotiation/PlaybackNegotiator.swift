import Foundation
import JellyfinAPI
import SerafinCore

/// Asks the server how to play an item, given Serafin's ``JellyfinAPI/DeviceProfile/serafin(maxBitrate:)``, and
/// turns the answer into a ``PlaybackPlan``.
public struct PlaybackNegotiator: Sendable {
    private let client: JellyfinClient
    private let userID: String

    /// Creates a negotiator.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    public init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    /// The plan for playing `itemID` with `options`.
    ///
    /// - Throws: A ``PlaybackError`` when the server can't offer a playable version, or SerafinCore's
    ///   `SerafinError` when it can't be reached or no longer accepts the sign-in.
    public func plan(for itemID: String, options: PlaybackOptions) async throws -> PlaybackPlan {
        let body = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: true,
            audioStreamIndex: options.audioStreamIndex,
            deviceProfile: .serafin(maxBitrate: options.maxBitrate),
            enableDirectPlay: options.allowsDirectPlay,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: false,
            maxStreamingBitrate: options.maxBitrate ?? DeviceProfile.uncappedBitrate,
            mediaSourceID: options.mediaSourceID,
            startTimeTicks: Ticks.from(options.startPosition),
            subtitleStreamIndex: options.subtitleStreamIndex,
            userID: userID
        )
        let response: PlaybackInfoResponse
        do {
            response = try await client.send(Paths.getPostedPlaybackInfo(itemID: itemID, body)).value
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        return try Self.plan(from: response, itemID: itemID, options: options, client: client)
    }

    /// Chooses a version and a delivery from the server's answer: the original file when the server allows it,
    /// otherwise the HLS stream the server prepared.
    static func plan(
        from response: PlaybackInfoResponse,
        itemID: String,
        options: PlaybackOptions,
        client: JellyfinClient
    ) throws -> PlaybackPlan {
        if let code = response.errorCode {
            throw PlaybackError(code)
        }
        let sources = response.mediaSources ?? []
        guard let source = sources.first(where: { $0.id == options.mediaSourceID }) ?? sources.first else {
            throw PlaybackError.notPlayable
        }

        let method: PlaybackPlan.Method
        let url: URL?
        if options.allowsDirectPlay, source.isSupportsDirectPlay == true {
            method = .directPlay
            url = staticURL(for: source, itemID: itemID, client: client)
        } else if let transcodingURL = source.transcodingURL {
            method = source.isSupportsDirectStream == true ? .directStream : .transcode
            url = client.url(path: transcodingURL)
        } else {
            throw PlaybackError.notPlayable
        }
        guard let url else { throw PlaybackError.notPlayable }
        return PlaybackPlan(
            itemID: itemID,
            mediaSource: source,
            url: url,
            method: method,
            playSessionID: response.playSessionID,
            startPosition: options.startPosition,
            audioStreamIndex: options.audioStreamIndex ?? source.defaultAudioStreamIndex,
            subtitleStreamIndex: options.subtitleStreamIndex ?? source.defaultSubtitleStreamIndex
        )
    }

    /// The address of the original file, with the token AVPlayer can't send as a header.
    private static func staticURL(for source: MediaSourceInfo, itemID: String, client: JellyfinClient) -> URL? {
        var parameters = Paths.GetVideoStreamParameters()
        parameters.isStatic = true
        parameters.mediaSourceID = source.id
        parameters.deviceID = client.configuration.deviceID
        parameters.tag = source.eTag
        return client.url(with: Paths.getVideoStream(itemID: itemID, parameters: parameters), queryAPIKey: true)
    }
}
