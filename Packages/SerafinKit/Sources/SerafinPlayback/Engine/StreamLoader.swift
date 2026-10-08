import AVFoundation
import SerafinCore
import Synchronization
import UniformTypeIdentifiers
import os

/// Stands between AVPlayer and the server: answers AVFoundation's certificate challenges with the user's pins, so a
/// server with a pinned self-signed certificate streams like any other, and serves the playlists that put the server's
/// subtitles in time with the picture.
///
/// AVPlayer does its own networking and never sees Serafin's URLSession delegate. It asks the asset's resource
/// loader delegate instead, which this is, for certificate challenges and for any address under a scheme it doesn't
/// know, such as the ones ``SubtitlePlaylists`` gives the playlists it rewrites. The loader fetches those through the
/// pinning delegate and hands AVPlayer the rewritten copies. Media never comes through it.
final class StreamLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    /// The queue AVFoundation calls the loader on.
    static let queue = DispatchQueue(label: "app.getserafin.serafin.stream-loader")
    /// The largest playlist the loader reads. A film's subtitle playlist is tens of kilobytes; this stops a server
    /// sending something huge.
    static let playlistLimit = 4 * 1024 * 1024

    private static let logger = Logger(serafinCategory: "player")

    private let pinning: PinningDelegate?
    private let session: URLSession
    /// The playlists on their way, by the loading request each answers, so AVFoundation can cancel them.
    private let loads = Mutex<[ObjectIdentifier: Task<Void, Never>]>([:])

    /// Creates a loader.
    ///
    /// - Parameters:
    ///   - pinning: The certificate pins to accept, for streams and for the playlists the loader fetches.
    ///   - configuration: How the loader fetches playlists. It's ephemeral; tests pass one with a stub protocol.
    init(pinning: PinningDelegate?, configuration: URLSessionConfiguration = .ephemeral) {
        self.pinning = pinning
        session = URLSession(configuration: configuration, delegate: pinning, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge
    ) -> Bool {
        guard let pinning else { return false }
        let (disposition, credential) = pinning.answer(to: authenticationChallenge)
        switch disposition {
        case .useCredential:
            guard let credential else { return false }
            authenticationChallenge.sender?.use(credential, for: authenticationChallenge)
            return true
        case .cancelAuthenticationChallenge:
            authenticationChallenge.sender?.cancel(authenticationChallenge)
            return true
        default:
            // The system's own handling, for a certificate it trusts.
            return false
        }
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let address = loadingRequest.request.url, let url = SubtitlePlaylists.serverURL(for: address) else {
            return false
        }
        let request = PlaylistRequest(request: loadingRequest)
        let key = ObjectIdentifier(loadingRequest)
        loads.withLock { loads in
            loads[key] = Task { [self] in
                defer { _ = self.loads.withLock { $0.removeValue(forKey: key) } }
                do {
                    let playlist = try await self.playlist(at: url)
                    request.respond(with: Data(SubtitlePlaylists.rewrite(playlist, from: url).utf8))
                } catch {
                    if !Task.isCancelled {
                        Self.logger.error("Couldn't load a playlist: \(error.localizedDescription, privacy: .private)")
                    }
                    request.fail(error)
                }
            }
        }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let load = loads.withLock { $0.removeValue(forKey: ObjectIdentifier(loadingRequest)) }
        load?.cancel()
    }

    /// The playlist at `url`, read up to ``playlistLimit``.
    private func playlist(at url: URL) async throws -> String {
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            guard body.count <= Self.playlistLimit else { throw URLError(.dataLengthExceedsMaximum) }
        }
        return String(decoding: body, as: UTF8.self)
    }
}

/// A loading request for a playlist, handed to the task that answers it. AVFoundation's requests aren't `Sendable`,
/// but each is answered once, from whichever thread the answer is ready on.
private struct PlaylistRequest: @unchecked Sendable {
    let request: AVAssetResourceLoadingRequest

    /// Answers with `playlist`, as much of it as was asked for.
    func respond(with playlist: Data) {
        guard !request.isCancelled else { return }
        if let information = request.contentInformationRequest {
            let type = UTType.m3uPlaylist.identifier
            if let allowed = information.allowedContentTypes, !allowed.isEmpty, !allowed.contains(type) {
                request.finishLoading(with: URLError(.cannotDecodeContentData))
                return
            }
            information.contentType = type
            information.contentLength = Int64(playlist.count)
        }
        if let data = request.dataRequest {
            let start = min(Int(clamping: data.requestedOffset), playlist.count)
            let available = playlist.count - start
            let length = data.requestsAllDataToEndOfResource ? available : min(data.requestedLength, available)
            if length > 0 {
                data.respond(with: playlist.subdata(in: start..<start + length))
            }
        }
        request.finishLoading()
    }

    /// Answers with `error`.
    func fail(_ error: any Error) {
        guard !request.isCancelled else { return }
        request.finishLoading(with: error)
    }
}
