import AVFoundation
import JellyfinAPI
import Observation
import SerafinCore
import os

#if canImport(UIKit)
    import AVKit
#endif

/// What the player is doing.
public enum PlaybackState: Equatable, Sendable {
    /// Nothing is loaded.
    case idle
    /// Asking the server how to play, or waiting for the first frames.
    case loading
    /// Loaded and waiting to start.
    case ready
    /// Playing.
    case playing
    /// Paused by the user.
    case paused
    /// Played to the end.
    case ended
    /// Couldn't play; ``PlayerEngine/failure`` says why.
    case failed
}

/// Plays one item at a time with AVPlayer, the way the server negotiated it, and keeps the server told where
/// playback is.
///
/// Screens read ``state``, ``elapsed``, ``duration``, ``buffered`` and ``rate``, and call the control methods.
/// Picture in Picture, AirPlay and Now Playing hang off ``player``.
@Observable @MainActor public final class PlayerEngine {
    /// What the player is doing.
    public private(set) var state = PlaybackState.idle
    /// How far into the item playback is.
    public private(set) var elapsed = Duration.zero
    /// How long the item is, once known.
    public private(set) var duration = Duration.zero
    /// How far ahead of the start the player has loaded.
    public private(set) var buffered = Duration.zero
    /// The playback speed the user chose, from 0.75 to 2.
    public private(set) var rate: Float = 1
    /// The item playing.
    public private(set) var item: BaseItemDto?
    /// How the current item is delivered, with its audio and subtitle streams.
    public private(set) var plan: PlaybackPlan?
    /// Why playback failed, when ``state`` is ``PlaybackState/failed``.
    public private(set) var failure: (any Error)?
    /// The episode after the one playing, for autoplay. Nil for movies and last episodes.
    public private(set) var nextItem: BaseItemDto?

    /// The player, for the video layer, Picture in Picture, AirPlay and Now Playing.
    public let player = AVPlayer()

    private static let logger = Logger(serafinCategory: "player")

    private let client: JellyfinClient
    private let negotiator: PlaybackNegotiator
    private let nextEpisode: NextEpisode
    private let streamLoader: PinnedStreamLoader
    private var options = PlaybackOptions()
    private var reporter: ProgressReporter?
    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservation: NSKeyValueObservation?
    private var endObserver: (any NSObjectProtocol)?
    private var reportingTask: Task<Void, Never>?
    /// Where to seek once the item is ready, before playing.
    private var pendingStart: Duration?
    /// Whether to start playing once the item is ready and at its start position.
    private var playsWhenReady = false
    /// True while a new item seeks to its start, so the brief pause there doesn't show as paused.
    private var isStarting = false
    #if canImport(UIKit)
        private var details: NowPlayingDetails?
        private var nowPlaying: NowPlaying?
        /// Picture in Picture for the player screen's video layer, once the screen has shown it.
        public private(set) var pictureInPicture: AVPictureInPictureController?
    #endif

    /// Creates an engine for the signed-in account.
    ///
    /// - Parameters:
    ///   - client: The account's client.
    ///   - userID: The account's user ID.
    ///   - pinning: The certificate pins to accept for streams, so a pinned self-signed server plays.
    public init(client: JellyfinClient, userID: String, pinning: PinningDelegate?) {
        self.client = client
        self.negotiator = PlaybackNegotiator(client: client, userID: userID)
        self.nextEpisode = NextEpisode(client: client, userID: userID)
        self.streamLoader = PinnedStreamLoader(pinning: pinning)
        player.allowsExternalPlayback = true
        observePlayer()
    }

    isolated deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        reportingTask?.cancel()
        clearItemObservations()
    }

    // MARK: - Loading

    /// Negotiates `item` with the server and starts playing it at `options.startPosition`.
    ///
    /// Anything already playing is stopped and reported first.
    public func load(_ item: BaseItemDto, options: PlaybackOptions) async {
        await stopReporting()
        self.item = item
        self.options = options
        nextItem = nil
        failure = nil
        elapsed = options.startPosition
        state = .loading
        PlaybackAudioSession.activate()
        do {
            guard let itemID = item.id else { throw PlaybackError.notPlayable }
            let plan = try await negotiator.plan(for: itemID, options: options)
            install(plan, startingAt: options.startPosition, playing: true)
            reporter = ProgressReporter(client: client, plan: plan)
            await reporter?.start(at: options.startPosition, isPaused: false)
            startReporting()
        } catch is CancellationError {
            state = .idle
        } catch {
            fail(error)
        }
        if item.type == .episode {
            nextItem = try? await nextEpisode.after(item)
        }
    }

    /// Stops playback, reports where it stopped and unloads the item.
    public func stop() async {
        player.pause()
        await stopReporting()
        reporter = nil
        player.replaceCurrentItem(with: nil)
        clearItemObservations()
        item = nil
        plan = nil
        nextItem = nil
        state = .idle
        PlaybackAudioSession.deactivate()
    }

    // MARK: - Lock Screen and Picture in Picture

    /// Sets what the Lock Screen and Control Center show for the item.
    ///
    /// - Parameters:
    ///   - title: The movie or episode title.
    ///   - subtitle: The show and episode number, for an episode.
    ///   - artwork: A JPEG of the artwork, if one has loaded.
    public func describe(title: String, subtitle: String?, artwork: Data?) {
        #if canImport(UIKit)
            details = NowPlayingDetails(title: title, subtitle: subtitle, artwork: artwork)
            player.currentItem?.externalMetadata = details?.metadata ?? []
        #endif
    }

    #if canImport(UIKit)
        /// Gives Picture in Picture the layer showing the video. ``PlayerSurface`` calls this.
        func attachPictureInPicture(to layer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            let controller = AVPictureInPictureController(playerLayer: layer)
            controller?.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPicture = controller
        }
    #endif

    // MARK: - Controls

    /// Starts or resumes playback at the chosen speed.
    public func play() {
        guard player.currentItem != nil else { return }
        if state == .ended {
            // Playing again after the end starts over, as a new playback on the server.
            Task {
                await seek(to: .zero)
                player.playImmediately(atRate: rate)
                await reporter?.start(at: .zero, isPaused: false)
                startReporting()
            }
            return
        }
        player.playImmediately(atRate: rate)
        report()
    }

    /// Pauses playback.
    public func pause() {
        player.pause()
        report()
    }

    /// Plays when paused and pauses when playing.
    public func togglePlayPause() {
        if state == .playing { pause() } else { play() }
    }

    /// Moves to `position`, clamped to the item.
    public func seek(to position: Duration) async {
        let target = min(max(position, .zero), duration > .zero ? duration : position)
        elapsed = target
        await player.seek(to: CMTime(target), toleranceBefore: .zero, toleranceAfter: .zero)
        if state == .ended {
            state = player.timeControlStatus == .playing ? .playing : .paused
        }
        report()
    }

    /// Moves forward, or back for a negative number, by `seconds`.
    public func skip(by seconds: Double) async {
        await seek(to: elapsed + .milliseconds(Int64(seconds * 1000)))
    }

    /// Plays at `rate`, such as 1.5 for one and a half times speed.
    public func setRate(_ rate: Float) {
        self.rate = rate
        player.defaultRate = rate
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
    }

    // MARK: - Tracks

    /// Plays the audio stream with server index `streamIndex`.
    ///
    /// When the loaded asset carries that track, the switch happens in place. Otherwise the server is asked again
    /// for a stream with that audio, and playback resumes where it was.
    public func selectAudio(_ streamIndex: Int) async {
        guard let plan, streamIndex != plan.audioStreamIndex else { return }
        if await selectInPlace(streamIndex, characteristic: .audible, among: plan.streams(.audio)) {
            self.plan = plan.with(audio: streamIndex)
            return
        }
        var options = self.options
        options.audioStreamIndex = streamIndex
        await renegotiate(options)
    }

    /// Shows the subtitle stream with server index `streamIndex`, or turns subtitles off for nil.
    ///
    /// Subtitles inside the loaded asset switch in place. Others mean asking the server again: subtitles the
    /// player can't read from the original file come back in an HLS stream, and styled or image subtitles are
    /// burned into the picture.
    public func selectSubtitle(_ streamIndex: Int?) async {
        guard let plan else { return }
        let wanted = streamIndex ?? -1
        guard wanted != plan.subtitleStreamIndex else { return }
        let subtitles = plan.streams(.subtitle)
        if streamIndex == nil, plan.method != .transcode || !isBurnedIn(plan.subtitleStreamIndex, in: subtitles) {
            await deselectLegible()
            self.plan = plan.with(subtitle: -1)
            return
        }
        if let streamIndex, await selectInPlace(streamIndex, characteristic: .legible, among: subtitles) {
            self.plan = plan.with(subtitle: streamIndex)
            return
        }
        var options = self.options
        options.subtitleStreamIndex = wanted
        let stream = subtitles.first { $0.index == streamIndex }
        // Only text tracks inside an MP4 play from the original file; anything else needs the server's HLS stream.
        options.allowsDirectPlay = stream == nil || (stream?.isExternal != true && stream?.codec == "mov_text")
        await renegotiate(options)
    }

    // MARK: - Helpers

    /// Loads a plan's stream, to start at `start` and play once it's there when `playing` is true.
    private func install(_ plan: PlaybackPlan, startingAt start: Duration, playing: Bool) {
        self.plan = plan
        let asset = AVURLAsset(url: plan.url)
        asset.resourceLoader.setDelegate(streamLoader, queue: PinnedStreamLoader.queue)
        let playerItem = AVPlayerItem(asset: asset)
        pendingStart = start > .zero ? start : nil
        playsWhenReady = playing
        clearItemObservations()
        observe(playerItem)
        #if canImport(UIKit)
            playerItem.externalMetadata = details?.metadata ?? []
            if nowPlaying == nil {
                nowPlaying = NowPlaying(engine: self)
            }
            nowPlaying?.becomeActive()
        #endif
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = rate
    }

    /// Asks the server again with new options, then picks up where playback was.
    private func renegotiate(_ newOptions: PlaybackOptions) async {
        guard let item, let itemID = item.id else { return }
        var options = newOptions
        options.startPosition = elapsed
        let wasPlaying = player.timeControlStatus == .playing
        state = .loading
        do {
            let plan = try await negotiator.plan(for: itemID, options: options)
            self.options = options
            install(plan, startingAt: options.startPosition, playing: wasPlaying)
            await reporter?.replace(with: plan, at: options.startPosition, isPaused: !wasPlaying)
        } catch is CancellationError {
        } catch {
            fail(error)
        }
    }

    /// Selects the track for `streamIndex` in the loaded asset, matching the server's stream to the asset's option by
    /// position among streams of its kind. Returns false when the asset doesn't carry it.
    private func selectInPlace(
        _ streamIndex: Int,
        characteristic: AVMediaCharacteristic,
        among streams: [MediaStream]
    ) async -> Bool {
        let carried = streams.filter { $0.isExternal != true }
        guard
            let playerItem = player.currentItem,
            let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic),
            group.options.count == carried.count,
            let position = carried.firstIndex(where: { $0.index == streamIndex })
        else { return false }
        playerItem.select(group.options[position], in: group)
        return true
    }

    private func deselectLegible() async {
        guard
            let playerItem = player.currentItem,
            let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible)
        else { return }
        playerItem.select(nil, in: group)
    }

    private func isBurnedIn(_ streamIndex: Int?, in streams: [MediaStream]) -> Bool {
        guard let streamIndex, streamIndex >= 0 else { return false }
        return streams.first { $0.index == streamIndex }?.deliveryMethod == .encode
    }

    private func fail(_ error: any Error) {
        Self.logger.error("Playback failed: \(String(describing: error), privacy: .private)")
        failure = error
        state = .failed
        player.pause()
        Task { await stopReporting() }
    }

    // MARK: - Reporting

    private func startReporting() {
        reportingTask?.cancel()
        reportingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ProgressReporter.interval)
                guard let self, !Task.isCancelled else { return }
                await self.reporter?.progress(at: self.elapsed, isPaused: self.state != .playing)
            }
        }
    }

    private func stopReporting() async {
        reportingTask?.cancel()
        reportingTask = nil
        await reporter?.stop(at: elapsed)
    }

    /// Reports the current position right away, as after a pause, resume or seek.
    private func report() {
        guard let reporter else { return }
        let position = elapsed
        let isPaused = player.timeControlStatus != .playing
        Task { await reporter.progress(at: position, isPaused: isPaused) }
    }

    // MARK: - Observation

    private func observePlayer() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.timeChanged(time)
            }
        }
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.statusChanged() }
        }
    }

    private func observe(_ playerItem: AVPlayerItem) {
        itemObservations = [
            playerItem.observe(\.status, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.itemStatusChanged() }
            },
            playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.bufferChanged() }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.didPlayToEnd()
            }
        }
    }

    private func clearItemObservations() {
        itemObservations.removeAll()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func timeChanged(_ time: CMTime) {
        guard state != .loading, time.isNumeric else { return }
        elapsed = Duration(time)
    }

    private func statusChanged() {
        guard !isStarting, state != .failed, state != .ended, player.currentItem?.status == .readyToPlay else { return }
        switch player.timeControlStatus {
        case .playing: state = .playing
        case .paused: state = .paused
        case .waitingToPlayAtSpecifiedRate: break
        @unknown default: break
        }
    }

    private func itemStatusChanged() {
        guard let playerItem = player.currentItem else { return }
        switch playerItem.status {
        case .readyToPlay:
            let length = playerItem.duration
            if length.isNumeric {
                duration = Duration(length)
            } else if let ticks = plan?.mediaSource.runTimeTicks {
                duration = Ticks.duration(ticks)
            }
            let start = pendingStart
            pendingStart = nil
            let playing = playsWhenReady
            playsWhenReady = false
            isStarting = true
            Task {
                if let start {
                    await player.seek(to: CMTime(start), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                isStarting = false
                if playing {
                    player.playImmediately(atRate: rate)
                } else if state == .loading {
                    state = .ready
                }
            }
        case .failed:
            Self.logger.error(
                "The player item failed: \(playerItem.error?.localizedDescription ?? "", privacy: .private)"
            )
            fail(PlaybackError.playerFailed)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func bufferChanged() {
        guard let range = player.currentItem?.loadedTimeRanges.first?.timeRangeValue else { return }
        let end = CMTimeRangeGetEnd(range)
        if end.isNumeric {
            buffered = Duration(end)
        }
    }

    private func didPlayToEnd() {
        elapsed = duration
        state = .ended
        Task { await stopReporting() }
    }
}

extension PlaybackPlan {
    /// The same plan with a different audio stream selected.
    func with(audio streamIndex: Int) -> PlaybackPlan {
        PlaybackPlan(
            itemID: itemID,
            mediaSource: mediaSource,
            url: url,
            method: method,
            playSessionID: playSessionID,
            startPosition: startPosition,
            audioStreamIndex: streamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
    }

    /// The same plan with a different subtitle stream selected, or -1 for none.
    func with(subtitle streamIndex: Int) -> PlaybackPlan {
        PlaybackPlan(
            itemID: itemID,
            mediaSource: mediaSource,
            url: url,
            method: method,
            playSessionID: playSessionID,
            startPosition: startPosition,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: streamIndex
        )
    }
}

extension CMTime {
    /// A CMTime for `duration`, in milliseconds.
    init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        self.init(value: seconds * 1000 + attoseconds / 1_000_000_000_000_000, timescale: 1000)
    }
}

extension Duration {
    /// A duration for `time`, which must be numeric.
    init(_ time: CMTime) {
        self = .milliseconds(Int64((time.seconds * 1000).rounded()))
    }
}
