import AVFoundation
import JellyfinAPI
import Observation
import SerafinCore
import os

#if canImport(UIKit)
    import AVKit
    import Synchronization
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
    /// Whether the next episode plays by itself after a countdown, as the account's Play Next Episode Automatically
    /// setting says. On until the account says otherwise.
    public private(set) var playsNextEpisodeAutomatically = true
    /// The stretches the server marked in the item, such as its intro, in order and without overlaps. Empty when it
    /// marked none.
    public private(set) var segments: [PlaybackSegment] = []
    /// Whether playback is held up waiting for data.
    public private(set) var isWaiting = false
    /// The subtitles showing, which the player's sheet checks. Settings decide them as each video starts, from the
    /// subtitle mode, the account's languages and the audio, and the sheet changes them.
    public private(set) var subtitleSelection = SubtitleSelection.off
    /// Subtitles picked in the sheet that are on their way in a new stream from the server, or nil.
    public private(set) var pendingSubtitleSelection: SubtitleSelection?
    /// The subtitles iOS generates from what's playing, or nil where iOS doesn't offer them. They only show when
    /// picked. iOS doesn't offer them in a stream that carries text subtitles in their language, so once it has offered
    /// them for a video they stay on offer, and picking them loads the video again without its text subtitles.
    public private(set) var generatedSubtitles: GeneratedSubtitles?
    /// The subtitles picked in the player for what's playing, or nil while Settings' choice stands. An episode that
    /// plays on from the one before keeps them.
    public private(set) var subtitleChoice: SubtitleChoice?
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
    private let segmentRepository: SegmentRepository
    private let streamLoader: StreamLoader
    /// Reads the account's playback preferences, for Settings' subtitle mode and autoplay, or nil to leave subtitles
    /// to the server and play next episodes by themselves.
    private let playbackPreferences: (@Sendable () async throws -> PlaybackPreferences)?
    /// Settings' subtitle rules for what's playing, or nil when the account's settings couldn't be read.
    @ObservationIgnored private var subtitleRules: SubtitleRules?
    /// The languages the viewer reads, most wanted first: Settings' subtitle language, or the device's languages.
    private var viewerLanguages: [String] {
        subtitleRules?.languages ?? Locale.preferredLanguages.compactMap(SubtitleRules.language)
    }
    /// The generated subtitles a stream of the video playing has offered the viewer, so they stay on offer in a
    /// stream that doesn't offer them, as one with text subtitles in their language.
    @ObservationIgnored private var offeredGenerated: GeneratedSubtitles?
    /// The legible option the engine selected in the current item, so a change made by anything else is undone.
    @ObservationIgnored private var legible: LegibleSelection?
    /// How many times a legible selection the engine didn't make has been undone in the current item.
    @ObservationIgnored private var reassertions = 0
    /// Goes up with every stream asked for, so an answer to an older request doesn't replace a newer one.
    @ObservationIgnored private var streamRequest = 0
    /// The item playing through the stream loader's playlists, which put its subtitles in time with the picture, or
    /// nil when the item plays the server's playlists as they are. See ``SubtitlePlaylists``.
    @ObservationIgnored private var retimedItem: AVPlayerItem?
    private var options = PlaybackOptions()
    private var reporter: ProgressReporter?
    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservation: NSKeyValueObservation?
    private var endObserver: (any NSObjectProtocol)?
    /// Hears AVPlayer change the item's media selection, as when it picks subtitles by itself.
    private var selectionObserver: (any NSObjectProtocol)?
    /// Fetches the server's playlist for the subtitle diagnostics, with the account's certificate pins.
    private let diagnosticsSession: URLSession
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
        /// Called when Picture in Picture ends without returning to the app, closed from its window, or when it fails
        /// to start, so the app can stop playback if nothing else shows the video.
        @ObservationIgnored public var pictureInPictureDidClose: (() -> Void)?
        /// Picture in Picture's wait for a player screen to show the video it's handing back.
        @ObservationIgnored private var pendingRestore: PictureInPictureRestore?
    #endif

    /// Creates an engine for the signed-in account.
    ///
    /// - Parameters:
    ///   - client: The account's client.
    ///   - userID: The account's user ID.
    ///   - pinning: The certificate pins to accept for streams, so a pinned self-signed server plays.
    ///   - playbackPreferences: Reads the account's playback preferences, for the subtitles each video starts with
    ///     and whether next episodes play by themselves. Nil leaves subtitles to the server, with autoplay on.
    public init(
        client: JellyfinClient,
        userID: String,
        pinning: PinningDelegate?,
        playbackPreferences: (@Sendable () async throws -> PlaybackPreferences)? = nil
    ) {
        self.client = client
        self.negotiator = PlaybackNegotiator(client: client, userID: userID)
        self.nextEpisode = NextEpisode(client: client, userID: userID)
        self.segmentRepository = SegmentRepository(client: client)
        self.streamLoader = StreamLoader(pinning: pinning)
        self.playbackPreferences = playbackPreferences
        diagnosticsSession = URLSession(configuration: .ephemeral, delegate: pinning, delegateQueue: nil)
        player.allowsExternalPlayback = true
        // Every subtitle selection is the engine's own. Left on, AVPlayer picks subtitles by itself, such as the ones
        // iOS 27 generates from the audio, on top of any the server burns into the picture.
        player.appliesMediaSelectionCriteriaAutomatically = false
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
        diagnosticsSession.finishTasksAndInvalidate()
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
    ///
    /// The subtitles it starts with come from Settings' subtitle mode, the account's languages and the audio, as
    /// ``SubtitleRules`` decide, rather than from the server, which would bring back the last subtitles picked for the
    /// video whatever Settings say.
    ///
    /// - Parameters:
    ///   - item: The movie or episode.
    ///   - options: What to ask the server for.
    ///   - keepsSubtitleChoice: Whether the subtitles picked in the player for what played before carry on, as for an
    ///     episode playing on from the last. Otherwise Settings' choice applies again.
    public func load(_ item: BaseItemDto, options: PlaybackOptions, keepsSubtitleChoice: Bool = false) async {
        let asked = ContinuousClock.now
        generation += 1
        let load = generation
        // A stream still on its way for what played before is no longer wanted.
        streamRequest += 1
        let request = streamRequest
        await stopReporting()
        guard load == generation else { return }
        self.item = item
        self.options = options
        plan = nil
        subtitleSelection = .off
        pendingSubtitleSelection = nil
        generatedSubtitles = nil
        offeredGenerated = nil
        if !keepsSubtitleChoice {
            subtitleChoice = nil
        }
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
            async let marked = segmentRepository.segments(of: itemID, isEpisode: item.type == .episode)
            async let preferences = Self.read(playbackPreferences)
            var plan = try await negotiator.plan(for: itemID, options: options)
            guard load == generation else { return }
            let account = await preferences
            guard load == generation else { return }
            let rules = account.map { SubtitleRules(preferences: $0.languages) }
            subtitleRules = rules
            playsNextEpisodeAutomatically = account?.playsNextEpisodeAutomatically ?? true
            let subtitles = Self.startingSubtitles(carrying: subtitleChoice, rules: rules, in: plan)
            // The server picked by its own defaults, so it's asked again when the subtitles need another stream.
            if subtitles.serverIndex != (plan.subtitleStreamIndex ?? -1) {
                var chosen = Self.optionsAskingAgain(options, for: plan)
                chosen.subtitleStreamIndex = subtitles.serverIndex
                chosen.allowsDirectPlay = Self.allowsDirectPlay(showing: subtitles.serverIndex, in: plan)
                plan = try await negotiator.plan(for: itemID, options: chosen)
                guard load == generation else { return }
                self.options = chosen
            }
            Self.logger.debug(
                "Playing by \(String(describing: plan.method), privacy: .public), planned in \((ContinuousClock.now - asked).loggedSeconds, privacy: .public)"
            )
            guard
                await install(
                    plan, subtitles: subtitles, startingAt: options.startPosition, playing: true, request: request)
                    != nil,
                load == generation, let plan = self.plan
            else { return }
            reporter = ProgressReporter(client: client, plan: plan)
            await reporter?.start(at: options.startPosition, isPaused: false)
            startReporting()
            let found = await marked
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
        streamRequest += 1
        player.pause()
        #if canImport(UIKit)
            pictureInPicture?.stopPictureInPicture()
        #endif
        await stopReporting()
        reporter = nil
        player.replaceCurrentItem(with: nil)
        clearItemObservations()
        retimedItem = nil
        legible = nil
        item = nil
        plan = nil
        subtitleSelection = .off
        pendingSubtitleSelection = nil
        generatedSubtitles = nil
        offeredGenerated = nil
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
            view.setFillsBounds(fillsScreen, animated: false)
            hostedVideoView = view
            setUpPictureInPicture(for: view.playerLayer)
            return view
        }

        /// Whether the picture fills the screen, cropping its edges, rather than fitting inside it with black bars.
        /// It stays as chosen from one video to the next.
        public private(set) var fillsScreen = false

        /// Fills the screen with the picture, cropping its edges, or fits the picture inside it.
        ///
        /// - Parameters:
        ///   - fills: Whether the picture fills the screen.
        ///   - animated: Whether the picture grows or shrinks into place, which Reduce Motion turns off.
        public func setFillsScreen(_ fills: Bool, animated: Bool) {
            fillsScreen = fills
            hostedVideoView?.setFillsBounds(fills, animated: animated)
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

        /// Starts Picture in Picture from the player screen's video, as when the screen is put away while it plays.
        /// Check ``isPictureInPicturePossible`` first; ``pictureInPictureDidStart`` follows once it has started, or
        /// ``pictureInPictureDidClose`` if it can't.
        public func startPictureInPicture() {
            guard let pictureInPicture, !pictureInPicture.isPictureInPictureActive else { return }
            pictureInPicture.startPictureInPicture()
        }

        /// Brings the video back from Picture in Picture, as when the player screen opens again.
        public func stopPictureInPicture() {
            pictureInPicture?.stopPictureInPicture()
        }

        /// The player screen showing the video is on screen, so Picture in Picture can hand the video back into it.
        func surfaceEnteredWindow() {
            finishRestore()
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
                // KVO can call from any thread, so the handlers are Sendable rather than the main actor's, and hop.
                controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
                    @Sendable [weak self] controller, _ in
                    let isPossible = controller.isPictureInPicturePossible
                    Task { @MainActor in
                        Self.logger.debug("Picture in Picture possible: \(isPossible, privacy: .public)")
                        self?.isPictureInPicturePossible = isPossible
                    }
                },
                controller.observe(\.isPictureInPictureActive, options: [.initial, .new]) {
                    @Sendable [weak self] controller, _ in
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
                on(AVAudioSession.routeChangeNotification) { $0.audioRouteChanged() },
            ]
        }

        /// Sound moved, as to or from AirPlay. An Apple TV plays the stream from its address, and can't reach the
        /// stream loader's playlists from there, so while AirPlay is on the item plays the server's playlists as they
        /// are, and once it's off, the loader's again, with the subtitles in time. The old item plays until the new
        /// one is in, as when the server sends a new stream.
        private func audioRouteChanged() {
            guard let plan, let playerItem = player.currentItem, state != .loading, pendingSubtitleSelection == nil,
                Self.retimesSubtitles(in: plan), (playerItem === retimedItem) == Self.isAirPlaying
            else { return }
            streamRequest += 1
            let request = streamRequest
            let playing = player.timeControlStatus != .paused
            Self.logger.debug(
                "Loading the stream again for AirPlay \(Self.isAirPlaying ? "on" : "off", privacy: .public)")
            Task {
                await install(plan, subtitles: subtitleSelection, startingAt: nil, playing: playing, request: request)
            }
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
            // Going home can reach the background before Picture in Picture starts, and the layer lets go of the
            // player there, so it takes it back for the floating window.
            hostedVideoView?.playerLayer.player = player
        }

        fileprivate func pictureInPictureStarted() {
            pictureInPictureDidStart?()
        }

        /// Picture in Picture stopped, or couldn't start. Unless it handed the video back to the app, it was closed.
        fileprivate func pictureInPictureEnded(restored: Bool) {
            isPictureInPictureEngaged = false
            if !isSurfaceShowing {
                hostedVideoView?.playerLayer.player = nil
            }
            if !restored {
                pictureInPictureDidClose?()
            }
        }

        /// Picture in Picture is handing the video back to the app. The app brings back a player screen, and Picture in
        /// Picture is told it may finish once that screen is on screen: told any sooner, it hands the video to a
        /// layer that isn't on screen yet, and AVKit pauses it.
        fileprivate func restoreUserInterface(_ restore: PictureInPictureRestore) {
            pendingRestore?.finish()
            pendingRestore = restore
            restoreFromPictureInPicture?()
            if isSurfaceShowing, hostedVideoView?.window != nil {
                // A player screen is up already, as when Picture in Picture started on the way to the background.
                finishRestore()
                return
            }
            // A screen that never comes doesn't hold Picture in Picture open.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.finishRestore(restore)
            }
        }

        /// Lets Picture in Picture finish handing the video back, if it's waiting.
        ///
        /// - Parameter restore: The hand-back to finish, or nil for whichever is waiting.
        private func finishRestore(_ restore: PictureInPictureRestore? = nil) {
            guard let pendingRestore, restore == nil || restore === pendingRestore else { return }
            self.pendingRestore = nil
            pendingRestore.finish()
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
    /// for a stream with that audio, and playback resumes where it was. Unless subtitles were picked in the player,
    /// Settings' subtitles follow the new audio's language, as For Other Languages turns them on for a foreign one.
    public func selectAudio(_ streamIndex: Int) async {
        guard let plan, streamIndex != plan.audioStreamIndex else { return }
        let switched = plan.with(audio: streamIndex)
        var subtitles = subtitleSelection
        if subtitleChoice == nil, let subtitleRules {
            subtitles = subtitleRules.selection(among: plan.streams(.subtitle), audioLanguage: switched.audioLanguage)
        }
        if !Self.needsNewStream(toShow: subtitles, in: plan), let playerItem = player.currentItem,
            await select(streamIndex, characteristic: .audible, among: Self.carriedAudio(of: plan), in: playerItem),
            player.currentItem === playerItem
        {
            self.plan = switched
            await reporter?.update(switched)
            // Generated subtitles come from the audio playing, so they follow it.
            if subtitles != subtitleSelection || subtitles == .generated {
                _ = showInPlace(subtitles)
            }
            return
        }
        var options = self.options
        options.audioStreamIndex = streamIndex
        options.subtitleStreamIndex = subtitles.serverIndex
        options.allowsDirectPlay = Self.allowsDirectPlay(showing: subtitles.serverIndex, in: plan)
        await renegotiate(options, subtitles: subtitles)
    }

    /// Shows `selection`, as picked in the player's sheet. The pick stands over Settings for the rest of what's
    /// playing, and for episodes that play on from it.
    ///
    /// Text subtitles in the stream and iOS's generated ones switch in place. Others mean asking the server again:
    /// subtitles the player can't read from the original file come back as text in an HLS stream, and styled or image
    /// subtitles are burned into the picture. Subtitles burned in only change with a new stream, without them. The old
    /// stream plays until the new one is ready, and either way only one set of subtitles ever shows.
    public func selectSubtitles(_ selection: SubtitleSelection) async {
        guard let plan, selection != subtitleSelection || pendingSubtitleSelection != nil else { return }
        subtitleChoice = Self.choice(for: selection, in: plan)
        if selection == subtitleSelection {
            // Picking what shows again lets go of other subtitles still on their way.
            cancelStreamRequest()
            return
        }
        if !Self.needsNewStream(toShow: selection, in: plan), showInPlace(selection) {
            return
        }
        var options = self.options
        options.subtitleStreamIndex = selection.serverIndex
        options.allowsDirectPlay = Self.allowsDirectPlay(showing: selection.serverIndex, in: plan)
        logSubtitles("picked \(selection), asking the server for a new stream")
        await renegotiate(options, subtitles: selection)
    }

    /// Whether showing `selection` takes a new stream from the server rather than a switch in the loaded one: when
    /// subtitles are burned into the picture now, or the ones wanted aren't in the stream as text.
    nonisolated static func needsNewStream(toShow selection: SubtitleSelection, in plan: PlaybackPlan) -> Bool {
        if isBurnedIn(plan.streamSubtitleStreamIndex, in: plan.streams(.subtitle)) {
            return true
        }
        guard case .stream(let index) = selection else { return false }
        return !carriedSubtitles(of: plan).contains { $0.index == index }
    }

    /// Whether a stream showing `streamIndex`, or -1 for none, may be the original file: only with no subtitles or a
    /// text track inside an MP4. Anything else needs the server's HLS stream.
    nonisolated static func allowsDirectPlay(showing streamIndex: Int, in plan: PlaybackPlan) -> Bool {
        guard streamIndex >= 0, let stream = plan.streams(.subtitle).first(where: { $0.index == streamIndex }) else {
            return true
        }
        return stream.isExternal != true && stream.codec == "mov_text"
    }

    /// The subtitles a video starts with: those picked in the player for the video before, when this one carries on
    /// from it and has them; otherwise what Settings' `rules` say; or, when the account's settings couldn't be read,
    /// the server's own choice.
    nonisolated static func startingSubtitles(
        carrying choice: SubtitleChoice?,
        rules: SubtitleRules?,
        in plan: PlaybackPlan
    ) -> SubtitleSelection {
        switch choice {
        case .off:
            return .off
        case .generated:
            return .generated
        case .language:
            if let choice, let index = streamIndex(for: choice, in: plan), index >= 0 {
                return .stream(index)
            }
        case nil:
            break
        }
        if let rules {
            return rules.selection(among: plan.streams(.subtitle), audioLanguage: plan.audioLanguage)
        }
        let server = plan.subtitleStreamIndex ?? -1
        return server >= 0 ? .stream(server) : .off
    }

    /// `selection` as a choice that can carry on to another episode: off, generated, or the language and kind of the
    /// stream, or nil for a stream with no language to match.
    nonisolated static func choice(for selection: SubtitleSelection, in plan: PlaybackPlan) -> SubtitleChoice? {
        switch selection {
        case .off:
            return .off
        case .generated:
            return .generated
        case .stream(let index):
            guard let stream = plan.streams(.subtitle).first(where: { $0.index == index }),
                let language = stream.language, !language.isEmpty
            else { return nil }
            return .language(
                language, isForced: stream.isForced == true, isHearingImpaired: stream.isHearingImpaired == true)
        }
    }

    /// The server's subtitle index for `choice` in `plan`: -1 for none, as for off and generated subtitles, otherwise a
    /// subtitle in the same language, the same kind if there is one, or nil when there's none in that language.
    nonisolated static func streamIndex(for choice: SubtitleChoice, in plan: PlaybackPlan) -> Int? {
        switch choice {
        case .off, .generated:
            return -1
        case .language(let language, let isForced, let isHearingImpaired):
            let sameLanguage = plan.streams(.subtitle).filter { $0.language == language }
            let match =
                sameLanguage.first {
                    ($0.isForced == true) == isForced && ($0.isHearingImpaired == true) == isHearingImpaired
                }
                ?? sameLanguage.first { ($0.isForced == true) == isForced } ?? sameLanguage.first
            return match?.index
        }
    }

    /// `options` for asking the server again for the version `plan` plays. They name the version: Jellyfin honours a
    /// chosen audio or subtitle stream only when the request names the version it belongs to, and goes back to its
    /// defaults otherwise, such as subtitles that Settings says always show.
    nonisolated static func optionsAskingAgain(_ options: PlaybackOptions, for plan: PlaybackPlan) -> PlaybackOptions {
        var options = options
        options.mediaSourceID = plan.mediaSourceID
        return options
    }

    // MARK: - Helpers

    /// Loads a plan's stream, to start at `start` and play once it's there when `playing` is true, with its audio and
    /// `subtitles` selected before the first frame. Does nothing when a newer stream has been asked for meanwhile.
    ///
    /// - Parameters:
    ///   - start: Where to start, or nil for where the stream it replaces has got to as it's replaced.
    ///   - request: The ``streamRequest`` this stream answers.
    /// - Returns: Where the stream starts, or nil when a newer stream was asked for.
    @discardableResult
    private func install(
        _ plan: PlaybackPlan,
        subtitles: SubtitleSelection,
        startingAt start: Duration?,
        playing: Bool,
        request: Int
    ) async -> Duration? {
        // AirPlay hands an Apple TV the stream's address, and it can't reach the stream loader's playlists from there.
        let retimes = Self.retimesSubtitles(in: plan) && !Self.isAirPlaying
        let loaderURL = retimes ? SubtitlePlaylists.loaderURL(for: plan.url) : nil
        let asset = AVURLAsset(url: loaderURL ?? plan.url)
        asset.resourceLoader.setDelegate(streamLoader, queue: StreamLoader.queue)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.textStyleRules = subtitleStyle.textStyleRules
        // Picked before the item goes in, so not even its first frame shows other subtitles.
        async let legibleGroup = try? asset.loadMediaSelectionGroup(for: .legible)
        async let audibleGroup = try? asset.loadMediaSelectionGroup(for: .audible)
        let (legibleOptions, audibleOptions) = await (legibleGroup, audibleGroup)
        guard request == streamRequest else { return nil }
        if let audio = plan.audioStreamIndex, let audibleOptions {
            Self.select(audio, among: Self.carriedAudio(of: plan), in: audibleOptions, of: playerItem)
        }
        let shown = select(subtitles, in: legibleOptions, of: playerItem, playing: plan)
        self.plan = plan.with(subtitle: shown.serverIndex)
        subtitleSelection = shown
        pendingSubtitleSelection = nil
        let start = start ?? currentPosition()
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
        retimedItem = loaderURL == nil ? nil : playerItem
        player.allowsExternalPlayback = loaderURL == nil
        player.replaceCurrentItem(with: playerItem)
        player.defaultRate = rate
        logSubtitles("loaded, tracks picked")
        return start
    }

    /// Selects the legible option the engine chose in `playerItem` again, if anything else changed it.
    private func reassertLegible(in playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem, let legible,
            playerItem.currentMediaSelection.selectedMediaOption(in: legible.group) != legible.option
        else { return }
        playerItem.select(legible.option, in: legible.group)
    }

    /// Where the item playing has got to: the player's own time once the item has reached its start, otherwise the
    /// position it's on its way to.
    private func currentPosition() -> Duration {
        if let pendingStart {
            return pendingStart
        }
        let time = player.currentTime()
        guard !isStarting, player.currentItem?.status == .readyToPlay, time.isNumeric else { return elapsed }
        return Duration(time)
    }

    /// Selects `subtitles` among `group`'s options in `playerItem`, which plays `plan`, and remembers the selection so
    /// a change made by anything else is undone. Subtitles burned into the picture, and none, select no option at all.
    /// Returns the subtitles that show: off when the ones wanted aren't there.
    private func select(
        _ subtitles: SubtitleSelection,
        in group: AVMediaSelectionGroup?,
        of playerItem: AVPlayerItem,
        playing plan: PlaybackPlan
    ) -> SubtitleSelection {
        reassertions = 0
        guard let group else {
            legible = nil
            generatedSubtitles = offeredGenerated
            // With nothing for the player to draw, only subtitles burned into the picture can show.
            return Self.isBurnedIn(subtitles.serverIndex, in: plan.streams(.subtitle)) ? subtitles : .off
        }
        let options = Self.legibleOptions(of: group, in: playerItem)
        let generated = Self.generatedPosition(
            among: options, audioLanguage: plan.audioLanguage, viewerLanguages: viewerLanguages)
        if let generated {
            offeredGenerated = GeneratedSubtitles(
                languageTag: group.options[generated].extendedLanguageTag,
                isTranslation: Self.isTranslation(options[generated], audioLanguage: plan.audioLanguage))
        }
        generatedSubtitles = offeredGenerated ?? Self.withheldGenerated(among: options, in: plan)
        let (position, shown) = Self.legiblePosition(
            for: subtitles, in: plan, among: options, viewerLanguages: viewerLanguages)
        let option = position.map { group.options[$0] }
        legible = LegibleSelection(group: group, option: option)
        playerItem.select(option, in: group)
        return shown
    }

    /// Shows `selection` in the loaded stream, without asking the server. Returns false when the stream can't show
    /// it, and changes nothing then.
    private func showInPlace(_ selection: SubtitleSelection) -> Bool {
        guard let plan, let playerItem = player.currentItem else { return false }
        let group = legible?.group
        guard group != nil || selection == .off else { return false }
        let options = group.map { Self.legibleOptions(of: $0, in: playerItem) } ?? []
        let showable = Self.legiblePosition(for: selection, in: plan, among: options, viewerLanguages: viewerLanguages)
        guard showable.shown == selection else { return false }
        // A stream on its way with other subtitles is no longer wanted.
        cancelStreamRequest()
        let shown = select(selection, in: group, of: playerItem, playing: plan)
        let changed = plan.with(subtitle: shown.serverIndex)
        self.plan = changed
        subtitleSelection = shown
        let position = elapsed
        let isPaused = player.timeControlStatus != .playing
        Task { [reporter] in
            await reporter?.update(changed)
            await reporter?.progress(at: position, isPaused: isPaused)
        }
        logSubtitles("picked \(selection), in place")
        return true
    }

    /// Lets go of any stream on its way from the server, as when a pick in place supersedes it, and goes back to
    /// showing what the player is doing.
    private func cancelStreamRequest() {
        streamRequest += 1
        pendingSubtitleSelection = nil
        if state == .loading, player.currentItem?.status == .readyToPlay {
            statusChanged()
        }
    }

    /// The audio streams the loaded asset carries, in order: the file's own tracks, or the one audio the server put in
    /// its stream.
    nonisolated static func carriedAudio(of plan: PlaybackPlan) -> [MediaStream] {
        plan.streams(.audio).filter { $0.isExternal != true }
    }

    /// The subtitle streams the loaded asset carries as text, in order. The original file carries only its own text
    /// tracks. The server's HLS stream carries every text subtitle it can send as WebVTT, including ones in separate
    /// files, but only when it was asked for one of them: a stream asked for with subtitles off or burned in lists
    /// none. Subtitles burned into the picture aren't tracks at all.
    nonisolated static func carriedSubtitles(of plan: PlaybackPlan) -> [MediaStream] {
        let subtitles = plan.streams(.subtitle)
        if plan.method == .directPlay {
            return subtitles.filter { $0.isExternal != true && $0.deliveryMethod != .encode }
        }
        let text = subtitles.filter { $0.deliveryMethod == .hls }
        return text.contains { $0.index == plan.streamSubtitleStreamIndex } ? text : []
    }

    /// Whether `plan`'s stream needs its subtitles put in time with the picture: text subtitles in the server's HLS
    /// stream of fragmented MP4 segments, which Jellyfin times for MPEG-TS. See ``SubtitlePlaylists``.
    nonisolated static func retimesSubtitles(in plan: PlaybackPlan) -> Bool {
        plan.method != .directPlay && !carriedSubtitles(of: plan).isEmpty && SubtitlePlaylists.isFragmentedMP4(plan.url)
    }

    #if canImport(UIKit)
        /// Whether sound is going to an AirPlay device, such as an Apple TV that AVPlayer would hand the video to.
        private static var isAirPlaying: Bool {
            AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        }
    #else
        private static let isAirPlaying = false
    #endif

    /// Asks the server again with new options for the version playing, then picks up where playback is, showing
    /// `subtitles` in the new stream.
    private func renegotiate(_ newOptions: PlaybackOptions, subtitles: SubtitleSelection) async {
        guard let item, let itemID = item.id else { return }
        streamRequest += 1
        let request = streamRequest
        let options = plan.map { Self.optionsAskingAgain(newOptions, for: $0) } ?? newOptions
        self.options = options
        pendingSubtitleSelection = subtitles == subtitleSelection ? nil : subtitles
        let wasPlaying = player.timeControlStatus == .playing
        state = .loading
        do {
            var asked = options
            asked.startPosition = elapsed
            let plan = try await negotiator.plan(for: itemID, options: asked)
            guard request == streamRequest else { return }
            Self.logger.debug("Playing again by \(String(describing: plan.method), privacy: .public)")
            // The old stream plays on meanwhile, so the new one starts where it has got to.
            guard
                let start = await install(
                    plan, subtitles: subtitles, startingAt: nil, playing: wasPlaying, request: request),
                request == streamRequest, let installed = self.plan
            else { return }
            await reporter?.replace(with: installed, at: start, isPaused: !wasPlaying)
        } catch is CancellationError {
        } catch {
            guard request == streamRequest else { return }
            pendingSubtitleSelection = nil
            fail(error)
        }
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
        guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: characteristic) else {
            return false
        }
        return Self.select(streamIndex, among: carried, in: group, of: playerItem)
    }

    /// Selects the option for `streamIndex` in `group`, by its position among the `carried` streams. Returns false
    /// when the counts don't line up, so nothing is guessed.
    @discardableResult
    private static func select(
        _ streamIndex: Int,
        among carried: [MediaStream],
        in group: AVMediaSelectionGroup,
        of playerItem: AVPlayerItem
    ) -> Bool {
        guard group.options.count == carried.count,
            let position = carried.firstIndex(where: { $0.index == streamIndex })
        else { return false }
        playerItem.select(group.options[position], in: group)
        return true
    }

    /// What the engine needs to know about each of `group`'s options in `playerItem`.
    private static func legibleOptions(of group: AVMediaSelectionGroup, in playerItem: AVPlayerItem) -> [LegibleOption]
    {
        let selectable = selectableOptions(in: group, of: playerItem)
        return group.options.map { option in
            LegibleOption(
                isGenerated: option.hasMediaCharacteristic(.machineGenerated),
                isTranslation: option.hasMediaCharacteristic(.languageTranslation),
                isClosedCaptions: option.mediaType == .closedCaption,
                language: SubtitleRules.language(option.extendedLanguageTag ?? option.locale?.identifier),
                isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
                isHearingImpaired: option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility),
                isSelectable: selectable?.contains(option) ?? true
            )
        }
    }

    /// The options in `group` that can show anything now, where iOS says: iOS 27 reports it for options that depend
    /// on others, such as subtitles generated from one audio track. Nil where the SDK can't say.
    static func selectableOptions(in group: AVMediaSelectionGroup, of playerItem: AVPlayerItem)
        -> [AVMediaSelectionOption]?
    {
        // The iOS 27 SDK comes with Swift 6.4, so older Xcodes skip this.
        #if compiler(>=6.4)
            if #available(iOS 27, macOS 27, *) {
                return playerItem.selectableMediaSelectionOptions(in: group)
            }
        #endif
        return nil
    }

    /// Where among an item's legible `options` the option for `selection` is, or nil to select none, with the
    /// subtitles that then show. Subtitles burned into the picture select none and still show.
    ///
    /// Text subtitles are matched among the options the stream itself carries, leaving out iOS's generated subtitles
    /// and the closed captions the player looks for in the video, which the server never lists. When there's an
    /// option for every stream, they match in order. AVPlayer merges subtitles it can't tell apart, though, such as
    /// several tracks of one language with the same name, and lists the first of them. Then a stream matches the
    /// option in its language and of its kind, forced or SDH.
    nonisolated static func legiblePosition(
        for selection: SubtitleSelection,
        in plan: PlaybackPlan,
        among options: [LegibleOption],
        viewerLanguages: [String] = []
    ) -> (position: Int?, shown: SubtitleSelection) {
        switch selection {
        case .off:
            return (nil, .off)
        case .generated:
            let position = generatedPosition(
                among: options, audioLanguage: plan.audioLanguage, viewerLanguages: viewerLanguages)
            return (position, position == nil ? .off : .generated)
        case .stream(let index):
            if isBurnedIn(index, in: plan.streams(.subtitle)) {
                return (nil, selection)
            }
            let carried = carriedSubtitles(of: plan)
            let authored = options.indices.filter { !options[$0].isGenerated && !options[$0].isClosedCaptions }
            guard let stream = carried.first(where: { $0.index == index }) else { return (nil, .off) }
            if authored.count == carried.count, let position = carried.firstIndex(where: { $0.index == index }) {
                return (authored[position], selection)
            }
            let position = mergedPosition(of: stream, among: carried, options: options, authored: authored)
            return (position, position == nil ? .off : selection)
        }
    }

    /// Where the option for `stream` is when AVPlayer has merged some of the `carried` streams: the `authored`
    /// option in the stream's language and of its kind, preferring an exact match of forced and SDH, then forced
    /// alone, then the language alone. Among several such options, the stream's place among its like matches them
    /// up when the counts agree; otherwise the first stands for them all, as AVPlayer keeps the first it merges.
    nonisolated static func mergedPosition(
        of stream: MediaStream,
        among carried: [MediaStream],
        options: [LegibleOption],
        authored: [Int]
    ) -> Int? {
        let language = SubtitleRules.language(stream.language)
        let isForced = stream.isForced == true
        let isHearingImpaired = stream.isHearingImpaired == true
        let kinds: [(LegibleOption) -> Bool] = [
            { $0.language == language && $0.isForced == isForced && $0.isHearingImpaired == isHearingImpaired },
            { $0.language == language && $0.isForced == isForced },
            { $0.language == language },
        ]
        let streamKinds: [(MediaStream) -> Bool] = [
            {
                SubtitleRules.language($0.language) == language && ($0.isForced == true) == isForced
                    && ($0.isHearingImpaired == true) == isHearingImpaired
            },
            { SubtitleRules.language($0.language) == language && ($0.isForced == true) == isForced },
            { SubtitleRules.language($0.language) == language },
        ]
        for (matches, sameKind) in zip(kinds, streamKinds) {
            let candidates = authored.filter { matches(options[$0]) }
            guard let first = candidates.first else { continue }
            let siblings = carried.filter(sameKind)
            if candidates.count == siblings.count, let place = siblings.firstIndex(where: { $0.index == stream.index })
            {
                return candidates[place]
            }
            return first
        }
        return nil
    }

    /// Where among `options` the subtitles iOS generates for the viewer are: in the first of the viewer's
    /// `viewerLanguages` that iOS offers, else in the audio's language, or nil. Only options that can show anything
    /// count. iOS also offers translations into languages of its own choosing, as when the video already has subtitles
    /// in the audio's language, and one in neither the viewer's languages nor the audio's isn't offered.
    nonisolated static func generatedPosition(
        among options: [LegibleOption],
        audioLanguage: String?,
        viewerLanguages: [String] = []
    ) -> Int? {
        let generated = options.indices.filter { options[$0].isGenerated && options[$0].isSelectable }
        let wanted = viewerLanguages + [SubtitleRules.language(audioLanguage)].compactMap { $0 }
        for language in wanted {
            if let position = generated.first(where: { options[$0].language == language }) {
                return position
            }
        }
        return nil
    }

    /// Whether generated subtitles in `option` translate audio in `audioLanguage` rather than transcribe it: iOS marks
    /// them as a translation, or their language isn't the audio's.
    nonisolated static func isTranslation(_ option: LegibleOption, audioLanguage: String?) -> Bool {
        if option.isTranslation {
            return true
        }
        guard let language = option.language, let audio = SubtitleRules.language(audioLanguage) else { return false }
        return language != audio
    }

    /// The subtitles iOS would generate from the audio in a stream without text subtitles, when iOS holds them back
    /// from this one: it offers subtitles generated in another language, but none in the audio's, which `plan`'s
    /// stream carries as text. Nil otherwise.
    nonisolated static func withheldGenerated(among options: [LegibleOption], in plan: PlaybackPlan)
        -> GeneratedSubtitles?
    {
        guard let audio = SubtitleRules.language(plan.audioLanguage),
            options.contains(where: { $0.isGenerated && $0.language != audio }),
            !options.contains(where: { $0.isGenerated && $0.language == audio }),
            carriedSubtitles(of: plan).contains(where: { SubtitleRules.language($0.language) == audio })
        else { return nil }
        return GeneratedSubtitles(languageTag: audio)
    }

    /// Whether the subtitles `streamIndex` names are burned into the picture.
    nonisolated static func isBurnedIn(_ streamIndex: Int?, in streams: [MediaStream]) -> Bool {
        guard let streamIndex, streamIndex >= 0 else { return false }
        return streams.first { $0.index == streamIndex }?.deliveryMethod == .encode
    }

    /// Reads the account's language preferences with `read`, or nil when there's nothing to read them with or they
    /// can't be read.
    private nonisolated static func read(
        _ read: (@Sendable () async throws -> PlaybackPreferences)?
    ) async -> PlaybackPreferences? {
        guard let read else { return nil }
        do {
            return try await read()
        } catch {
            Logger.playback.error(
                "Could not read the playback preferences: \(error.localizedDescription, privacy: .private)")
            return nil
        }
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
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor in self?.statusChanged() }
        }
    }

    private func observe(_ playerItem: AVPlayerItem) {
        itemObservations = [
            playerItem.observe(\.status, options: [.new]) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.itemStatusChanged() }
            },
            playerItem.observe(\.loadedTimeRanges, options: [.new]) { @Sendable [weak self] _, _ in
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
        selectionObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.mediaSelectionDidChangeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mediaSelectionChanged(in: playerItem)
            }
        }
    }

    /// Something changed `playerItem`'s media selection. The engine makes every subtitle selection itself, so a
    /// legible option it didn't select is undone, such as generated subtitles iOS picks by itself.
    private func mediaSelectionChanged(in playerItem: AVPlayerItem) {
        logSubtitles("media selection changed")
        guard player.currentItem === playerItem, let legible,
            playerItem.currentMediaSelection.selectedMediaOption(in: legible.group) != legible.option
        else { return }
        // A selection that won't stay undone isn't fought forever.
        guard reassertions < 3 else {
            Self.logger.error("Something keeps changing the subtitles")
            return
        }
        reassertions += 1
        Self.logger.debug("Undoing subtitles the engine didn't select")
        playerItem.select(legible.option, in: legible.group)
    }

    /// Logs every layer subtitles can come from after `event`, in debug builds. See ``SubtitleDiagnostics``.
    private func logSubtitles(_ event: String) {
        #if DEBUG
            Task {
                await SubtitleDiagnostics.log(
                    event, plan: plan, selection: subtitleSelection, player: player, session: diagnosticsSession)
            }
        #endif
    }

    private func clearItemObservations() {
        itemObservations.removeAll()
        for observer in [endObserver, selectionObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        selectionObserver = nil
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
            // As the item loads, AVPlayer applies the stream's own defaults over a selection made before, such as
            // the closed captions it marks as the default, so the engine's selection is made again before the
            // first frame shows.
            reassertLegible(in: playerItem)
            logSubtitles("ready to play")
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
        /// Whether Picture in Picture is handing the video back to the app. Set off the main thread ahead of the stop,
        /// so it's kept here rather than on the engine, where it could arrive after the stop.
        private let isRestoring = Mutex(false)

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
            isRestoring.withLock { $0 = false }
            withEngine { $0.pictureInPictureEnded(restored: false) }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
            let restored = isRestoring.withLock { isRestoring in
                defer { isRestoring = false }
                return isRestoring
            }
            withEngine { $0.pictureInPictureEnded(restored: restored) }
        }

        func pictureInPictureController(
            _ controller: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            isRestoring.withLock { $0 = true }
            let restore = PictureInPictureRestore(completionHandler)
            withEngine { $0.restoreUserInterface(restore) }
        }
    }

    /// AVKit's completion handler for handing the video back from Picture in Picture, carried to the main actor and
    /// called there once the player screen is on screen.
    ///
    /// Unchecked: AVKit calls the delegate on a background queue with a handler it doesn't mark as sendable, and this
    /// only ever calls it once, from the main actor.
    private final class PictureInPictureRestore: @unchecked Sendable {
        private let completion: (Bool) -> Void

        init(_ completion: @escaping (Bool) -> Void) {
            self.completion = completion
        }

        /// Tells Picture in Picture the app is ready for the video.
        func finish() {
            completion(true)
        }
    }
#endif

extension PlaybackPlan {
    /// The same plan with a different audio stream selected.
    func with(audio streamIndex: Int) -> PlaybackPlan {
        var plan = PlaybackPlan(
            itemID: itemID,
            mediaSource: mediaSource,
            url: url,
            method: method,
            playSessionID: playSessionID,
            startPosition: startPosition,
            audioStreamIndex: streamIndex,
            subtitleStreamIndex: subtitleStreamIndex
        )
        plan.negotiatedSubtitles = negotiatedSubtitles
        return plan
    }

    /// The same plan with a different subtitle stream selected, or -1 for none. The stream stays the one the server
    /// made, with the subtitles it carries.
    func with(subtitle streamIndex: Int) -> PlaybackPlan {
        var plan = PlaybackPlan(
            itemID: itemID,
            mediaSource: mediaSource,
            url: url,
            method: method,
            playSessionID: playSessionID,
            startPosition: startPosition,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: streamIndex
        )
        plan.negotiatedSubtitles = streamSubtitleStreamIndex
        return plan
    }
}

/// Subtitles iOS generates from a video's audio, which the player's sheet offers as one choice.
public struct GeneratedSubtitles: Hashable, Sendable {
    /// Their language, as a BCP 47 tag such as "en-US", when iOS says.
    public var languageTag: String?
    /// Whether iOS translates the audio into them, rather than writing down what's said.
    public var isTranslation: Bool

    /// Creates a description of generated subtitles.
    ///
    /// - Parameters:
    ///   - languageTag: Their language, as a BCP 47 tag, or nil when iOS doesn't say.
    ///   - isTranslation: Whether iOS translates the audio into them.
    public init(languageTag: String?, isTranslation: Bool = false) {
        self.languageTag = languageTag
        self.isTranslation = isTranslation
    }
}

/// What the engine needs to know about one of an item's legible options to choose among them.
struct LegibleOption: Equatable {
    /// Whether iOS generated it from the audio.
    var isGenerated: Bool
    /// Whether it's marked as a translation.
    var isTranslation: Bool
    /// Whether it's the closed captions the player looks for inside the video. The server never lists them, and they
    /// only show when the video carries them.
    var isClosedCaptions: Bool
    /// Its language, as ``SubtitleRules/language(_:)`` normalizes it.
    var language: String?
    /// Whether it holds forced subtitles only.
    var isForced: Bool
    /// Whether it's for the deaf and hard of hearing.
    var isHearingImpaired: Bool
    /// Whether it can show anything now.
    var isSelectable: Bool

    init(
        isGenerated: Bool = false,
        isTranslation: Bool = false,
        isClosedCaptions: Bool = false,
        language: String? = nil,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isSelectable: Bool = true
    ) {
        self.isGenerated = isGenerated
        self.isTranslation = isTranslation
        self.isClosedCaptions = isClosedCaptions
        self.language = language
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isSelectable = isSelectable
    }
}

/// The legible option the engine selected in an item, or nil for none, with the group it belongs to.
private struct LegibleSelection {
    let group: AVMediaSelectionGroup
    let option: AVMediaSelectionOption?
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
