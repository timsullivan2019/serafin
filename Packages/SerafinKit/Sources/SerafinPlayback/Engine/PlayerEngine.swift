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
/// AirPlay and Now Playing hang off ``player``. On iOS the engine also keeps the view showing the video, so Picture in
/// Picture can carry on after the player screen closes.
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
    /// The stretches the server marked in the item, such as its intro, in order. Empty when it marked none.
    public private(set) var segments: [PlaybackSegment] = []
    /// Whether playback is held up waiting for data.
    public private(set) var isWaiting = false
    /// How text subtitles look. A change shows straight away on what's playing.
    public var subtitleStyle = SubtitleStyle.standard {
        didSet {
            if subtitleStyle != oldValue {
                player.currentItem?.textStyleRules = subtitleStyle.textStyleRules
            }
        }
    }

    /// Whether the player is loading or waiting for data, so a spinner should show.
    public var isBuffering: Bool {
        state == .loading || isWaiting
    }

    /// The player, for the video layer, Picture in Picture, AirPlay and Now Playing.
    public let player = AVPlayer()

    private static let logger = Logger(serafinCategory: "player")

    private let client: JellyfinClient
    private let negotiator: PlaybackNegotiator
    private let nextEpisode: NextEpisode
    private let mediaSegments: MediaSegments
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
    /// How many seeks are under way. The player reports its old position until a seek lands, so the elapsed time
    /// holds at the target meanwhile.
    @ObservationIgnored private var seeksInFlight = 0
    /// Goes up with every load and stop, so a load that finishes after another has started, or after a stop, does
    /// nothing.
    @ObservationIgnored private var generation = 0
    #if canImport(UIKit)
        private var details: NowPlayingDetails?
        private var nowPlaying: NowPlaying?
        @ObservationIgnored private var hostedVideoView: PlayerLayerView?
        @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
        @ObservationIgnored private var pictureInPictureEvents: PictureInPictureEvents?
        @ObservationIgnored private var pictureInPictureObservations: [NSKeyValueObservation] = []
        /// Whether a player screen is showing the video.
        @ObservationIgnored private var isSurfaceShowing = false
        /// True from the moment Picture in Picture begins to start until it has stopped, so the video layer keeps
        /// the player meanwhile.
        @ObservationIgnored private var isPictureInPictureEngaged = false
        /// Whether something was playing as the app stopped being active, so playback carries on if iOS pauses it on
        /// the way to the background.
        @ObservationIgnored private var wasPlayingOnResign = false
        @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []
        /// Whether Picture in Picture can start now.
        public private(set) var isPictureInPicturePossible = false
        /// Whether the video is playing in Picture in Picture.
        public private(set) var isPictureInPictureActive = false
        /// Called once Picture in Picture has started, so the app can put the player screen away.
        @ObservationIgnored public var pictureInPictureDidStart: (() -> Void)?
        /// Called when the user returns from Picture in Picture to the app, so the app can bring back the player
        /// screen.
        @ObservationIgnored public var restoreFromPictureInPicture: (() -> Void)?
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
        self.mediaSegments = MediaSegments(client: client)
        self.streamLoader = PinnedStreamLoader(pinning: pinning)
        player.allowsExternalPlayback = true
        observePlayer()
        #if canImport(UIKit)
            observeLifecycle()
        #endif
    }

    isolated deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        reportingTask?.cancel()
        clearItemObservations()
        #if canImport(UIKit)
            for observer in lifecycleObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        #endif
    }

    // MARK: - Loading

    /// Negotiates `item` with the server and starts playing it at `options.startPosition`.
    ///
    /// Anything already playing is stopped and reported first.
    public func load(_ item: BaseItemDto, options: PlaybackOptions) async {
        generation += 1
        let load = generation
        await stopReporting()
        guard load == generation else { return }
        self.item = item
        self.options = options
        nextItem = nil
        segments = []
        failure = nil
        elapsed = options.startPosition
        state = .loading
        await PlaybackAudioSession.activate()
        guard load == generation else { return }
        do {
            guard let itemID = item.id else { throw PlaybackError.notPlayable }
            // Asked for alongside the plan, so an intro at the very start can be skipped from its first seconds, but
            // waited for only once playback has started, so a slow answer never holds the picture up.
            async let marked = try? mediaSegments.of(itemID)
            let plan = try await negotiator.plan(for: itemID, options: options)
            guard load == generation else { return }
            Self.logger.debug("Playing by \(String(describing: plan.method), privacy: .public)")
            install(plan, startingAt: options.startPosition, playing: true)
            reporter = ProgressReporter(client: client, plan: plan)
            await reporter?.start(at: options.startPosition, isPaused: false)
            startReporting()
            let found = await marked ?? []
            guard load == generation else { return }
            segments = found
        } catch is CancellationError {
            if load == generation {
                state = .idle
            }
            return
        } catch {
            if load == generation {
                fail(error)
            }
            return
        }
        if item.type == .episode {
            let next = try? await nextEpisode.after(item)
            if load == generation {
                nextItem = next
            }
        }
    }

    /// Stops playback, reports where it stopped and unloads the item.
    public func stop() async {
        generation += 1
        player.pause()
        #if canImport(UIKit)
            pictureInPicture?.stopPictureInPicture()
        #endif
        await stopReporting()
        reporter = nil
        player.replaceCurrentItem(with: nil)
        clearItemObservations()
        item = nil
        plan = nil
        nextItem = nil
        segments = []
        state = .idle
        await PlaybackAudioSession.deactivate()
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
            player.currentItem?.nowPlayingInfo = details?.nowPlayingInfo
        #endif
    }

    #if canImport(UIKit)
        /// The view showing the video, which ``PlayerSurface`` hosts.
        ///
        /// The engine keeps it from one player screen to the next. Picture in Picture is tied to its layer, so it
        /// carries on when the screen closes and returns to the next screen that shows the view.
        public var videoView: PlayerLayerView {
            if let hostedVideoView {
                return hostedVideoView
            }
            let view = PlayerLayerView()
            view.playerLayer.player = player
            hostedVideoView = view
            setUpPictureInPicture(for: view.playerLayer)
            return view
        }

        /// Starts Picture in Picture, or stops it when it is on.
        public func togglePictureInPicture() {
            guard let pictureInPicture else { return }
            if pictureInPicture.isPictureInPictureActive {
                pictureInPicture.stopPictureInPicture()
            } else {
                pictureInPicture.startPictureInPicture()
            }
        }

        /// Brings the video back from Picture in Picture, as when the player screen opens again.
        public func stopPictureInPicture() {
            pictureInPicture?.stopPictureInPicture()
        }

        /// A player screen started showing the video.
        func surfaceAppeared() {
            isSurfaceShowing = true
            hostedVideoView?.playerLayer.player = player
        }

        /// The player screen stopped showing the video. Unless Picture in Picture has the picture, the layer lets go
        /// of the player, because AVPlayer pauses in the background while a layer holds it, and the audio should
        /// carry on.
        func surfaceDisappeared() {
            isSurfaceShowing = false
            if !isPictureInPictureEngaged {
                hostedVideoView?.playerLayer.player = nil
            }
        }

        private func setUpPictureInPicture(for layer: AVPlayerLayer) {
            guard
                AVPictureInPictureController.isPictureInPictureSupported(),
                let controller = AVPictureInPictureController(playerLayer: layer)
            else {
                Self.logger.debug("Picture in Picture isn't supported here")
                return
            }
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            let events = PictureInPictureEvents(engine: self)
            controller.delegate = events
            pictureInPictureEvents = events
            pictureInPictureObservations = [
                controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
                    [weak self] controller, _ in
                    let isPossible = controller.isPictureInPicturePossible
                    Task { @MainActor in
                        Self.logger.debug("Picture in Picture possible: \(isPossible, privacy: .public)")
                        self?.isPictureInPicturePossible = isPossible
                    }
                },
                controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) { [weak self] controller, _ in
                    let isActive = controller.isPictureInPictureActive
                    Task { @MainActor in self?.isPictureInPictureActive = isActive }
                },
            ]
            pictureInPicture = controller
        }

        /// Follows the app in and out of the background, as when the device locks or the user goes home.
        private func observeLifecycle() {
            func on(_ name: Notification.Name, _ handle: @escaping @MainActor (PlayerEngine) -> Void)
                -> any NSObjectProtocol
            {
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if let self { handle(self) }
                    }
                }
            }
            lifecycleObservers = [
                on(UIApplication.willResignActiveNotification) { engine in
                    engine.wasPlayingOnResign = engine.player.timeControlStatus != .paused
                },
                on(UIApplication.didEnterBackgroundNotification) { $0.enteredBackground() },
                on(UIApplication.willEnterForegroundNotification) { $0.enteringForeground() },
            ]
        }

        /// The app went to the background. iOS pauses a player whose picture is on screen, so unless Picture in
        /// Picture has the picture, the layer lets go of the player and the film carries on as sound. If iOS paused it
        /// on the way, it plays on.
        private func enteredBackground() {
            if !isPictureInPictureEngaged {
                hostedVideoView?.playerLayer.player = nil
            }
            if wasPlayingOnResign, player.currentItem != nil, player.timeControlStatus == .paused, state != .ended {
                Self.logger.debug("Playing on after iOS paused for the background")
                player.playImmediately(atRate: rate)
            }
        }

        /// The app is coming back, so a player screen that's showing gets its picture back.
        private func enteringForeground() {
            if isSurfaceShowing || isPictureInPictureEngaged {
                hostedVideoView?.playerLayer.player = player
            }
        }

        fileprivate func pictureInPictureWillStart() {
            isPictureInPictureEngaged = true
        }

        fileprivate func pictureInPictureStarted() {
            pictureInPictureDidStart?()
        }

        fileprivate func pictureInPictureEnded() {
            isPictureInPictureEngaged = false
            if !isSurfaceShowing {
                hostedVideoView?.playerLayer.player = nil
            }
        }

        fileprivate func restoreUserInterface() {
            restoreFromPictureInPicture?()
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
        seeksInFlight += 1
        await player.seek(to: CMTime(target), toleranceBefore: .zero, toleranceAfter: .zero)
        seeksInFlight -= 1
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
        if await selectInPlace(streamIndex, characteristic: .audible, among: Self.carriedAudio(of: plan)) {
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
        if let streamIndex,
            await selectInPlace(streamIndex, characteristic: .legible, among: Self.carriedSubtitles(of: plan))
        {
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
        playerItem.textStyleRules = subtitleStyle.textStyleRules
        pendingStart = start > .zero ? start : nil
        playsWhenReady = playing
        clearItemObservations()
        observe(playerItem)
        #if canImport(UIKit)
            playerItem.externalMetadata = details?.metadata ?? []
            playerItem.nowPlayingInfo = details?.nowPlayingInfo
            if nowPlaying == nil {
                nowPlaying = NowPlaying(engine: self)
            }
            nowPlaying?.becomeActive()
        #endif
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = rate
        Task { await selectPlannedTracks(in: playerItem, for: plan) }
    }

    /// Picks the audio and subtitles the plan names in a newly loaded item.
    ///
    /// The server chooses them from the user's language preferences and marks them as the stream's defaults, but
    /// AVPlayer picks by the device's own settings: it plays the file's first audio, and shows subtitles only when the
    /// audio is in another language or the system's caption settings ask. With the plan's subtitles off, AVPlayer's
    /// choice stands, so captions the system asks for and forced subtitles still show.
    private func selectPlannedTracks(in playerItem: AVPlayerItem, for plan: PlaybackPlan) async {
        if let audio = plan.audioStreamIndex {
            await select(audio, characteristic: .audible, among: Self.carriedAudio(of: plan), in: playerItem)
        }
        if let subtitle = plan.subtitleStreamIndex, subtitle >= 0 {
            await select(subtitle, characteristic: .legible, among: Self.carriedSubtitles(of: plan), in: playerItem)
        }
    }

    /// The audio streams the loaded asset carries, in order: the file's own tracks, or the one audio the server put in
    /// its stream.
    nonisolated static func carriedAudio(of plan: PlaybackPlan) -> [MediaStream] {
        plan.streams(.audio).filter { $0.isExternal != true }
    }

    /// The subtitle streams the loaded asset carries as text, in order. The server's HLS stream carries every text
    /// subtitle it can send as WebVTT, including ones in separate files; the original file carries only its own text
    /// tracks. Subtitles burned into the picture aren't tracks at all.
    nonisolated static func carriedSubtitles(of plan: PlaybackPlan) -> [MediaStream] {
        let subtitles = plan.streams(.subtitle)
        if plan.method == .directPlay {
            return subtitles.filter { $0.isExternal != true && $0.deliveryMethod != .encode }
        }
        return subtitles.filter { $0.deliveryMethod == .hls }
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
            Self.logger.debug("Playing again by \(String(describing: plan.method), privacy: .public)")
            install(plan, startingAt: options.startPosition, playing: wasPlaying)
            await reporter?.replace(with: plan, at: options.startPosition, isPaused: !wasPlaying)
        } catch is CancellationError {
        } catch {
            fail(error)
        }
    }

    /// Selects the track for `streamIndex` in the loaded asset. Returns false when the asset doesn't carry it.
    ///
    /// - Parameter carried: The streams of that kind the asset carries, in order.
    private func selectInPlace(
        _ streamIndex: Int,
        characteristic: AVMediaCharacteristic,
        among carried: [MediaStream]
    ) async -> Bool {
        guard let playerItem = player.currentItem else { return false }
        return await select(streamIndex, characteristic: characteristic, among: carried, in: playerItem)
    }

    /// Selects the track for `streamIndex` in `playerItem`, matching the server's stream to the asset's option by
    /// position among the streams the asset carries. Returns false when the counts don't line up, so nothing is
    /// guessed.
    @discardableResult
    private func select(
        _ streamIndex: Int,
        characteristic: AVMediaCharacteristic,
        among carried: [MediaStream],
        in playerItem: AVPlayerItem
    ) async -> Bool {
        guard
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
        guard state != .loading, seeksInFlight == 0, time.isNumeric else { return }
        elapsed = Duration(time)
    }

    private func statusChanged() {
        isWaiting = player.currentItem != nil && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
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

#if canImport(UIKit)
    /// Hands Picture in Picture's delegate calls to the engine on the main actor. AVKit makes most of them on the main
    /// thread, but returning from Picture in Picture to the app arrives on a background queue.
    private final class PictureInPictureEvents: NSObject, AVPictureInPictureControllerDelegate {
        private weak var engine: PlayerEngine?

        init(engine: PlayerEngine) {
            self.engine = engine
        }

        /// Runs `work` with the engine on the main actor: straight away when called there, so the engine knows
        /// before the app moves on, and otherwise as soon as the main actor is free.
        private func withEngine(_ work: @escaping @MainActor @Sendable (PlayerEngine) -> Void) {
            let engine = engine
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    if let engine { work(engine) }
                }
            } else {
                Task { @MainActor in
                    if let engine { work(engine) }
                }
            }
        }

        func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
            withEngine { $0.pictureInPictureWillStart() }
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
            withEngine { $0.pictureInPictureStarted() }
        }

        func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: any Error
        ) {
            withEngine { $0.pictureInPictureEnded() }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
            withEngine { $0.pictureInPictureEnded() }
        }

        func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            withEngine { $0.restoreUserInterface() }
            completionHandler(true)
        }
    }
#endif

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
