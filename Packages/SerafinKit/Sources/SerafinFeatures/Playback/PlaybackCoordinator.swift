import Foundation
import JellyfinAPI
import Observation
import SerafinCore
import SerafinDesign
import SerafinPlayback

#if canImport(UIKit)
    import UIKit
#endif

/// What is playing, shared by the full-screen player and Picture in Picture.
///
/// It starts items on the account's ``PlayerEngine`` at their resume point, under the streaming cap Settings gives
/// for the network the device is on. Putting the player away hands a playing video to Picture in Picture, or stops
/// it. When playback stops it has every screen reload, so progress and played marks show. Without an engine, as in
/// previews, it only pretends to play.
@Observable @MainActor final class PlaybackCoordinator {
    /// Where to start an item.
    enum Start: Equatable {
        /// Where the user left off, or the beginning when they haven't started.
        case resume
        /// The beginning.
        case beginning
        /// A particular position, as when trying again after a failure.
        case position(Duration)
    }

    /// The movie or episode playing, or nil when nothing is.
    private(set) var nowPlaying: MediaItem?
    /// Whether the full-screen player is showing. Once it's put away while a video plays, Picture in Picture shows the
    /// video instead.
    var isPlayerPresented = false
    /// The control the full-screen player zooms out of and back into, such as the hero's play pill, or nil for the
    /// standard slide up.
    private(set) var zoomSource: String?

    /// Where Settings keeps whether putting the player away hands a playing video to Picture in Picture.
    static let minimizesToPictureInPictureKey = "minimizesToPictureInPicture"
    /// The engine playing for the signed-in account. Nil in previews.
    let engine: PlayerEngine?
    /// How text subtitles look, as picked in Settings. A change shows straight away on what's playing.
    var subtitleStyle: SubtitleStyle {
        didSet {
            guard subtitleStyle != oldValue else { return }
            subtitleStyle.save(in: defaults)
            engine?.subtitleStyle = subtitleStyle
        }
    }

    /// Whether a preview is pretending to play.
    private var isPretending = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Closes the full-screen player once the interface has turned upright.
    @ObservationIgnored private var closing: Task<Void, Never>?
    /// Whether the player is being put away into Picture in Picture, which hasn't started yet.
    @ObservationIgnored private var isDismissingToPictureInPicture = false
    /// Stops playback if Picture in Picture, asked to start, neither starts nor fails.
    @ObservationIgnored private var pictureInPictureFallback: Task<Void, Never>?
    @ObservationIgnored private let media: any MediaSource
    @ObservationIgnored private let actions: MediaActions
    @ObservationIgnored private let artwork: Artwork?
    @ObservationIgnored private let serverID: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isOnExpensiveNetwork: @MainActor () -> Bool

    /// Creates the coordinator.
    ///
    /// - Parameters:
    ///   - engine: The account's engine, or nil to pretend.
    ///   - media: The library, refreshed when playback stops.
    ///   - actions: Has the screens reload when playback stops.
    ///   - artwork: Loads the artwork the Lock Screen shows.
    ///   - serverID: The account's server, whose streaming caps apply. Nil in previews.
    ///   - defaults: Where Settings keeps the streaming caps and the subtitle style.
    ///   - isOnExpensiveNetwork: Whether the device is on cellular or a personal hotspot right now. Nil asks the app's
    ///     network watcher.
    init(
        engine: PlayerEngine? = nil,
        media: any MediaSource = SampleMediaSource(),
        actions: MediaActions = MediaActions(),
        artwork: Artwork? = nil,
        serverID: String? = nil,
        defaults: UserDefaults = .standard,
        isOnExpensiveNetwork: (@MainActor () -> Bool)? = nil
    ) {
        self.engine = engine
        self.media = media
        self.actions = actions
        self.artwork = artwork
        self.serverID = serverID
        self.defaults = defaults
        if let isOnExpensiveNetwork {
            self.isOnExpensiveNetwork = isOnExpensiveNetwork
        } else {
            // The watcher starts now rather than at the first video, since it takes a moment to learn the network.
            let network = NetworkWatcher.shared
            self.isOnExpensiveNetwork = { network.isExpensive }
        }
        subtitleStyle = SubtitleStyle.saved(in: defaults)
        engine?.subtitleStyle = subtitleStyle
    }

    /// Whether playback is running rather than paused.
    var isPlaying: Bool {
        guard let engine else { return isPretending }
        return engine.state == .playing
    }

    /// The most bits per second to stream from the account's server on the current network, or nil for no cap.
    var maxBitrate: Int? {
        PlaybackQuality.saved(onCellular: isOnExpensiveNetwork(), server: serverID, in: defaults).bitsPerSecond
    }

    /// Starts `item` and shows the full-screen player. Only movies and episodes play; a show or season plays from
    /// its page, which knows the episode to start.
    ///
    /// - Parameters:
    ///   - zoomSource: The control the player grows out of, or nil to slide up as usual.
    ///   - presentsPlayer: Whether the full-screen player shows. An episode that follows on in Picture in Picture
    ///     stays there.
    ///   - continuing: Whether this carries on from what was playing, as the next episode or a retry, so subtitles
    ///     picked in the player stay as they were rather than going back to Settings' default.
    func play(
        _ item: MediaItem, from start: Start = .resume, zoomSource: String? = nil, presentsPlayer: Bool = true,
        continuing: Bool = false
    ) {
        guard item.card.kind == .movie || item.card.kind == .episode else { return }
        nowPlaying = item
        if presentsPlayer {
            if !isPlayerPresented {
                self.zoomSource = zoomSource
            }
            isPlayerPresented = true
        }
        guard let engine, let source = item.source else {
            isPretending = true
            return
        }
        let options = PlaybackOptions(maxBitrate: maxBitrate, startPosition: Self.startPosition(of: item, from: start))
        #if canImport(UIKit)
            engine.pictureInPictureDidStart = { [weak self] in self?.pictureInPictureStarted() }
            engine.restoreFromPictureInPicture = { [weak self] in
                guard let self, nowPlaying != nil else { return }
                presentPlayer()
            }
            engine.pictureInPictureDidClose = { [weak self] in self?.pictureInPictureClosed() }
            // A video in Picture in Picture comes back into the player screen, which now plays this one. Not in the
            // background, where the next episode after one that ended carries on in the floating window.
            if presentsPlayer, engine.isPictureInPictureActive, UIApplication.shared.applicationState == .active {
                engine.stopPictureInPicture()
            }
        #endif
        let card = item.card
        let subtitle = card.episode == nil ? nil : card.eyebrowText
        engine.describe(title: card.title, subtitle: subtitle, artwork: nil)
        loading?.cancel()
        loading = Task { [artwork] in
            await engine.load(source, options: options, keepsSubtitleChoice: continuing)
            guard !Task.isCancelled, let jpeg = await Self.lockScreenArtwork(for: source, from: artwork) else { return }
            engine.describe(title: card.title, subtitle: subtitle, artwork: jpeg)
        }
    }

    /// The video ended with the player screen away, as in Picture in Picture, where Up Next can't show: an episode with
    /// a next one carries on into it there, and anything else stops.
    func endedWithoutThePlayer() {
        guard !isPlayerPresented, nowPlaying != nil else { return }
        guard let next = engine?.nextItem, let item = MediaItem(next) else {
            stop()
            return
        }
        play(item, from: .beginning, presentsPlayer: false, continuing: true)
    }

    /// Plays the episode after the one that just ended, with the subtitles picked in the player for it.
    func playNext() {
        guard let next = engine?.nextItem, let item = MediaItem(next) else {
            stop()
            return
        }
        play(item, from: .beginning, continuing: true)
    }

    /// Tries the item again from where playback was.
    func retry() {
        guard let nowPlaying else { return }
        play(nowPlaying, from: engine.map { .position($0.elapsed) } ?? .resume, continuing: true)
    }

    /// Pauses or resumes.
    func togglePlayPause() {
        guard let engine else {
            isPretending.toggle()
            return
        }
        engine.togglePlayPause()
    }

    /// Brings back the full-screen player for what is playing, out of Picture in Picture if need be.
    func showPlayer() {
        guard nowPlaying != nil else { return }
        presentPlayer()
        #if canImport(UIKit)
            engine?.stopPictureInPicture()
        #endif
    }

    /// Shows the full-screen player again, as when Picture in Picture hands the video back, which it's already
    /// doing, so it isn't asked to stop as well.
    ///
    /// The control the player first grew out of may have gone by now, with the screen behind changed while the video
    /// was away, so the player comes back as usual rather than zooming out of it.
    private func presentPlayer() {
        zoomSource = nil
        if closing != nil {
            // Changed course while the interface was turning upright to close: keep the player.
            closing?.cancel()
            closing = nil
            #if os(iOS)
                InterfaceOrientations.playerAppeared()
            #endif
        }
        isPlayerPresented = true
    }

    /// What putting the player away does.
    enum Dismissal: Equatable {
        /// The video carries on in Picture in Picture.
        case pictureInPicture
        /// Playback stops where it is, and the screen behind shows again.
        case stop
    }

    /// What putting the player away does: a video that's playing carries on in Picture in Picture, when Settings
    /// allows it and Picture in Picture can start. Anything else stops.
    static func dismissal(minimizesToPictureInPicture: Bool, isPlaying: Bool, isPictureInPicturePossible: Bool)
        -> Dismissal
    {
        minimizesToPictureInPicture && isPlaying && isPictureInPicturePossible ? .pictureInPicture : .stop
    }

    /// Whether putting the player away hands a playing video to Picture in Picture, as set in Settings: on unless
    /// turned off.
    static func minimizesToPictureInPicture(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: minimizesToPictureInPictureKey) as? Bool ?? true
    }

    /// Puts the full-screen player away, as its minimize button and a swipe down do. A video that's playing carries
    /// on in Picture in Picture when Settings allows it and Picture in Picture can start, and the player screen goes
    /// once it has. Otherwise playback stops where it is, the server hears where, and the screen behind shows again.
    func dismissPlayer() {
        #if canImport(UIKit)
            if let engine,
                Self.dismissal(
                    minimizesToPictureInPicture: Self.minimizesToPictureInPicture(in: defaults),
                    isPlaying: engine.state == .playing,
                    isPictureInPicturePossible: engine.isPictureInPicturePossible
                ) == .pictureInPicture
            {
                isDismissingToPictureInPicture = true
                engine.startPictureInPicture()
                // The player doesn't stay up waiting for a Picture in Picture that neither starts nor fails.
                pictureInPictureFallback?.cancel()
                pictureInPictureFallback = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self, isDismissingToPictureInPicture else { return }
                    isDismissingToPictureInPicture = false
                    stop()
                }
                return
            }
        #endif
        stop()
    }

    /// Picture in Picture has the video. Started in the app, from its button or by putting the player away, the
    /// player screen goes. Started by going home, the screen stays: putting it away in the background left it half
    /// gone, and coming back from Picture in Picture then showed a black screen.
    private func pictureInPictureStarted() {
        pictureInPictureFallback?.cancel()
        isDismissingToPictureInPicture = false
        #if canImport(UIKit)
            guard UIApplication.shared.applicationState == .active else { return }
        #endif
        closePlayer()
    }

    /// Picture in Picture ended without coming back to the app, or couldn't start. With no player screen to come
    /// back to, nothing is left to watch, so playback stops. With one, as when the app went home with the player up,
    /// the video waits there.
    private func pictureInPictureClosed() {
        pictureInPictureFallback?.cancel()
        let wasDismissing = isDismissingToPictureInPicture
        isDismissingToPictureInPicture = false
        guard nowPlaying != nil, !isPlayerPresented || wasDismissing else { return }
        stop()
    }

    /// Hides the full-screen player, then runs `closed`. On iPhone the interface first turns upright, so the player
    /// shrinks away in the same orientation as the screen behind it rather than over a sideways one.
    private func closePlayer(then closed: @escaping @MainActor () -> Void = {}) {
        #if os(iOS)
            if InterfaceOrientations.playerWillClose() {
                closing?.cancel()
                closing = Task { [weak self] in
                    try? await Task.sleep(for: Self.turnDuration)
                    guard !Task.isCancelled, let self else { return }
                    closing = nil
                    isPlayerPresented = false
                    closed()
                }
                return
            }
        #endif
        isPlayerPresented = false
        closed()
    }

    /// How long the interface takes to turn upright.
    private static let turnDuration = Duration.milliseconds(400)

    /// Stops playback, closes the player and Picture in Picture, and has the screens reload to show the new progress.
    func stop() {
        loading?.cancel()
        loading = nil
        pictureInPictureFallback?.cancel()
        isDismissingToPictureInPicture = false
        isPretending = false
        if isPlayerPresented {
            // The title stays until the player has gone, so the screen doesn't empty while it turns upright.
            closePlayer { [weak self] in self?.nowPlaying = nil }
        } else {
            nowPlaying = nil
        }
        guard let engine else { return }
        Task { [media, actions] in
            await engine.stop()
            await media.refresh()
            actions.reload()
        }
    }

    /// Where `item` starts.
    static func startPosition(of item: MediaItem, from start: Start) -> Duration {
        switch start {
        case .beginning:
            return .zero
        case .position(let position):
            return max(position, .zero)
        case .resume:
            guard let ticks = item.source?.userData?.playbackPositionTicks, ticks > 0 else { return .zero }
            return Ticks.duration(ticks)
        }
    }

    /// A JPEG of the item's thumbnail for the Lock Screen, or nil when it can't be had.
    private static func lockScreenArtwork(for item: BaseItemDto, from artwork: Artwork?) async -> Data? {
        #if canImport(UIKit)
            guard
                let artwork,
                let request = artwork.request(.landscape, of: item, width: 600, scale: 1),
                let image = try? await artwork.pipeline.image(for: request)
            else { return nil }
            return image.jpegData(compressionQuality: 0.85)
        #else
            return nil
        #endif
    }
}
