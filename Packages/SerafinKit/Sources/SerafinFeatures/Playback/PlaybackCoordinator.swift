import Foundation
import JellyfinAPI
import Observation
import SerafinCore
import SerafinDesign
import SerafinPlayback

/// What is playing, shared by the full-screen player and the mini player.
///
/// It starts items on the account's ``PlayerEngine`` at their resume point, under the streaming cap Settings gives
/// for the network the device is on. When playback stops it has every screen reload, so progress and played marks
/// show. Without an engine, as in previews, it only pretends to play.
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
    /// Whether the full-screen player is showing. The mini player shows instead while something plays.
    var isPlayerPresented = false
    /// The control the full-screen player zooms out of and back into, such as the hero's play pill, or nil for the
    /// standard slide up.
    private(set) var zoomSource: String?

    /// The zoom source of the mini player.
    static let miniPlayerZoomSource = "mini-player"
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
    ///   - isOnExpensiveNetwork: Whether the device is on cellular or a personal hotspot right now.
    init(
        engine: PlayerEngine? = nil,
        media: any MediaSource = SampleMediaSource(),
        actions: MediaActions = MediaActions(),
        artwork: Artwork? = nil,
        serverID: String? = nil,
        defaults: UserDefaults = .standard,
        isOnExpensiveNetwork: @escaping @MainActor () -> Bool = { NetworkWatcher.shared.isExpensive }
    ) {
        self.engine = engine
        self.media = media
        self.actions = actions
        self.artwork = artwork
        self.serverID = serverID
        self.defaults = defaults
        self.isOnExpensiveNetwork = isOnExpensiveNetwork
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
    /// - Parameter zoomSource: The control the player grows out of, or nil to slide up as usual.
    func play(_ item: MediaItem, from start: Start = .resume, zoomSource: String? = nil) {
        guard item.card.kind == .movie || item.card.kind == .episode else { return }
        nowPlaying = item
        if !isPlayerPresented {
            self.zoomSource = zoomSource
        }
        isPlayerPresented = true
        guard let engine, let source = item.source else {
            isPretending = true
            return
        }
        let options = PlaybackOptions(maxBitrate: maxBitrate, startPosition: Self.startPosition(of: item, from: start))
        #if canImport(UIKit)
            // Picture in Picture puts the player screen away when it starts, and brings it back on the way out.
            engine.pictureInPictureDidStart = { [weak self] in self?.closePlayer() }
            engine.restoreFromPictureInPicture = { [weak self] in self?.showPlayer() }
        #endif
        let card = item.card
        let subtitle = card.episode == nil ? nil : card.eyebrowText
        engine.describe(title: card.title, subtitle: subtitle, artwork: nil)
        loading?.cancel()
        loading = Task { [artwork] in
            await engine.load(source, options: options)
            guard !Task.isCancelled, let jpeg = await Self.lockScreenArtwork(for: source, from: artwork) else { return }
            engine.describe(title: card.title, subtitle: subtitle, artwork: jpeg)
        }
    }

    /// Plays the episode after the one that just ended.
    func playNext() {
        guard let next = engine?.nextItem, let item = MediaItem(next) else {
            stop()
            return
        }
        play(item, from: .beginning)
    }

    /// Tries the item again from where playback was.
    func retry() {
        guard let nowPlaying else { return }
        play(nowPlaying, from: engine.map { .position($0.elapsed) } ?? .resume)
    }

    /// Pauses or resumes.
    func togglePlayPause() {
        guard let engine else {
            isPretending.toggle()
            return
        }
        engine.togglePlayPause()
    }

    /// Brings back the full-screen player for what is playing, out of Picture in Picture if need be. It grows out of
    /// the mini player.
    func showPlayer() {
        guard nowPlaying != nil else { return }
        if closing != nil {
            // Changed course while the interface was turning upright to close: keep the player.
            closing?.cancel()
            closing = nil
            #if os(iOS)
                InterfaceOrientations.playerAppeared()
            #endif
        }
        zoomSource = Self.miniPlayerZoomSource
        isPlayerPresented = true
        #if canImport(UIKit)
            engine?.stopPictureInPicture()
        #endif
    }

    /// Puts the full-screen player away while playback carries on. It shrinks back into the control it came from.
    func minimize() {
        closePlayer()
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

    /// Stops playback, hides both players, and has the screens reload to show the new progress.
    func stop() {
        loading?.cancel()
        loading = nil
        isPretending = false
        if isPlayerPresented {
            // The mini player is going away too, so there's nothing to shrink into but the original control.
            if zoomSource == Self.miniPlayerZoomSource {
                zoomSource = nil
            }
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
