import CoreSpotlight
import SerafinCore
import SerafinDesign
import SerafinPlayback
import SwiftUI

/// The root of Serafin's interface: the connect flow until someone signs in, then the tabs, browsing as the
/// current account.
public struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppLock.self) private var lock: AppLock?
    @Environment(AppRequests.self) private var requests: AppRequests?

    /// Creates the root view. It expects the app's ``AppSession`` in the environment.
    public init() {}

    public var body: some View {
        Group {
            switch session.state {
            case .loading:
                Color.background
                    .ignoresSafeArea()
            case .signedOut:
                ConnectFlow()
            case .signedIn(let account):
                if let library = session.library {
                    let media = LiveMediaSource(library: library)
                    MainTabs(engine: session.player, media: media, artwork: session.artwork)
                        .environment(\.media, media)
                        .environment(\.artwork, session.artwork)
                        .environment(
                            \.signInEnded,
                            SignInEndedAction(account: account.key) { [session] in
                                Task { try? await session.signOut(account.key) }
                            }
                        )
                        // Another account starts on fresh tabs rather than the last account's screens.
                        .id(account.key)
                }
            }
        }
        .tint(.accentFallback)
        .appLock(lock)
        // Here rather than on the tabs, so a result tapped while the app is still starting isn't lost.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                requests?.send(.show(itemID: id))
            }
        }
        .task(id: SpotlightTrigger(state: session.state, isLockOn: lock?.isEnabled ?? false), priority: .background) {
            await updateSpotlight()
        }
    }

    /// Writes the signed-in library to Spotlight, or empties it when no one is signed in or the lock is on, since
    /// Spotlight would show the library to whoever holds the device.
    private func updateSpotlight() async {
        guard let spotlight = session.spotlight else { return }
        switch session.state {
        case .loading:
            return
        case .signedOut:
            await spotlight.removeAll()
        case .signedIn(let account):
            guard lock?.isEnabled != true else {
                await spotlight.removeAll()
                return
            }
            guard let library = session.library else { return }
            // Home's own requests go first.
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            let artwork = session.artwork
            await spotlight.update(account: account.key, media: LiveMediaSource(library: library)) { item in
                await PosterThumbnail.jpeg(of: item, from: artwork)
            }
        }
    }
}

/// What decides what Spotlight holds.
private struct SpotlightTrigger: Equatable {
    let state: AppSession.State
    let isLockOn: Bool
}

/// Home, Library, Search and Settings tabs, a sidebar on iPad, and the mini player in the tab bar while something
/// plays.
struct MainTabs: View {
    @State private var selection = AppTab.home
    @State private var paths = TabPaths()
    @State private var searchRequest = SearchRequest()
    @State private var playback: PlaybackCoordinator
    @State private var actions: MediaActions
    @Namespace private var playerZoom

    /// Creates the tabs.
    ///
    /// - Parameters:
    ///   - engine: The account's player engine, or nil to pretend to play.
    ///   - media: The library, which playback refreshes when it stops.
    ///   - artwork: Loads the artwork the Lock Screen shows.
    init(engine: PlayerEngine? = nil, media: any MediaSource = SampleMediaSource(), artwork: Artwork? = nil) {
        let actions = MediaActions()
        _actions = State(initialValue: actions)
        _playback = State(
            initialValue: PlaybackCoordinator(engine: engine, media: media, actions: actions, artwork: artwork)
        )
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(
                String(localized: "Home", bundle: .module, comment: "Title of the home tab."),
                systemImage: "house",
                value: AppTab.home
            ) {
                TabStack(path: $paths.home) { HomeView() }
            }
            Tab(
                String(localized: "Library", bundle: .module, comment: "Title of the library tab."),
                systemImage: "square.grid.2x2",
                value: AppTab.library
            ) {
                TabStack(path: $paths.library) { LibrariesView() }
            }
            Tab(
                String(localized: "Settings", bundle: .module, comment: "Title of the settings tab."),
                systemImage: "gearshape",
                value: AppTab.settings
            ) {
                TabStack(path: $paths.settings) { SettingsView() }
            }
            Tab(value: AppTab.search, role: .search) {
                TabStack(path: $paths.search) { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background {
            TabShortcuts(selection: $selection, searchRequest: $searchRequest)
        }
        .modifier(
            OutsideRequests(
                selection: $selection, paths: $paths, searchRequest: $searchRequest, playback: playback,
                actions: actions)
        )
        .environment(\.searchRequest, searchRequest)
        .modifier(TabChrome(playback: playback, playerZoom: playerZoom))
        .environment(\.playerZoomNamespace, playerZoom)
        .environment(playback)
        .environment(actions)
        // One place for the tap that confirms Mark as Played and Favourite, from a detail screen or a card's menu.
        .sensoryFeedback(trigger: actions.confirmation) { _, confirmation in confirmation?.feedback }
        .onChange(of: actions.confirmation) { _, confirmation in
            if let confirmation {
                AccessibilityNotification.Announcement(confirmation.announcement).post()
            }
        }
        .alert(
            actions.failure?.title ?? "",
            isPresented: Binding(get: { actions.failure != nil }, set: { if !$0 { actions.failure = nil } })
        ) {
            Button(String(localized: "OK", bundle: .module, comment: "Button that closes an alert.")) {}
        } message: {
            Text(actions.failure?.message ?? "")
        }
    }
}

/// Keyboard shortcuts that work anywhere in the tabs: Command-F searches, and while something plays, F opens the
/// full-screen player. The player handles its own keys, Space, the arrows and F to leave, so these step aside while it
/// shows.
private struct TabShortcuts: View {
    @Binding var selection: AppTab
    @Binding var searchRequest: SearchRequest
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        if !playback.isPlayerPresented {
            buttons
        }
    }

    private var buttons: some View {
        Group {
            Button(String(localized: "Search", bundle: .module, comment: "Title of the search tab.")) {
                selection = .search
                searchRequest = SearchRequest(number: searchRequest.number + 1)
            }
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityHidden(true)
            if playback.nowPlaying != nil {
                Button(
                    String(
                        localized: "Show Player", bundle: .module,
                        comment: "Keyboard shortcut that opens the full-screen player.")
                ) {
                    playback.showPlayer()
                }
                .keyboardShortcut("f", modifiers: [])
                .accessibilityHidden(true)
            }
        }
        // The buttons exist only for their shortcuts, which still show in the iPad's keyboard shortcut list. With no
        // size they're nothing VoiceOver or a finger can land on.
        .frame(width: 0, height: 0)
        .clipped()
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The app's tabs.
enum AppTab: Hashable {
    case home
    case library
    case search
    case settings
}

/// The screens pushed onto each tab, kept together so Siri and Spotlight can push onto them.
struct TabPaths: Equatable {
    var home: [Route] = []
    var library: [Route] = []
    var search: [Route] = []
    var settings: [Route] = []

    subscript(tab: AppTab) -> [Route] {
        get {
            switch tab {
            case .home: home
            case .library: library
            case .search: search
            case .settings: settings
            }
        }
        set {
            switch tab {
            case .home: home = newValue
            case .library: library = newValue
            case .search: search = newValue
            case .settings: settings = newValue
            }
        }
    }

    /// Pushes an item's page onto the tab showing, or onto Home from Settings, unless it's already on top.
    ///
    /// - Returns: The tab to show.
    mutating func show(_ id: String, from tab: AppTab) -> AppTab {
        let tab = tab == .settings ? AppTab.home : tab
        if self[tab].last != .item(id: id) {
            self[tab].append(.item(id: id))
        }
        return tab
    }
}

/// Does what Siri, Shortcuts and Spotlight ask, once the tabs show and the app lock is down.
private struct OutsideRequests: ViewModifier {
    @Binding var selection: AppTab
    @Binding var paths: TabPaths
    @Binding var searchRequest: SearchRequest
    let playback: PlaybackCoordinator
    let actions: MediaActions
    @Environment(AppRequests.self) private var requests: AppRequests?
    @Environment(AppLock.self) private var lock: AppLock?
    @Environment(\.media) private var media

    func body(content: Content) -> some View {
        content
            .onChange(of: Gate(request: requests?.pending, isOpen: lock?.isOpen ?? true), initial: true) { _, gate in
                guard gate.isOpen, let request = requests?.take() else { return }
                handle(request)
            }
    }

    /// What decides whether a request can go ahead.
    private struct Gate: Equatable {
        let request: AppRequests.Request?
        /// Whether the app lock lets it, which it doesn't until the owner unlocks.
        let isOpen: Bool
    }

    private func handle(_ request: AppRequests.Request) {
        switch request {
        case .show(let id):
            putPlayerAway()
            selection = paths.show(id, from: selection)
        case .play(let id):
            Task { await play(id) }
        case .search(let term):
            putPlayerAway()
            selection = .search
            // Without a term, as from the Search shortcut, the field waits for one.
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            searchRequest = SearchRequest(number: searchRequest.number + 1, term: term.isEmpty ? nil : term)
        }
    }

    /// Shrinks the full-screen player into the mini player, where playback carries on, so a page or results shown
    /// for a request don't go unseen under it.
    private func putPlayerAway() {
        if playback.isPlayerPresented {
            playback.minimize()
        }
    }

    /// Plays a movie or episode where the user left off, or a show's next episode. Anything else opens its page.
    private func play(_ id: String) async {
        do {
            let details = try await media.details(of: id)
            guard let playable = details.playable else {
                selection = paths.show(id, from: selection)
                return
            }
            playback.play(playable)
        } catch {
            actions.failure = UserMessage(error)
        }
    }
}

/// The tab bar's behaviour: the tab bar minimizes on scroll, the mini player rides in its accessory while something
/// plays, and the full-screen player covers everything. On iPad the tab bar can open into a sidebar.
private struct TabChrome: ViewModifier {
    @Bindable var playback: PlaybackCoordinator
    let playerZoom: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: playback.nowPlaying != nil) {
                    NowPlayingAccessory()
                }
                .fullScreenCover(isPresented: $playback.isPlayerPresented) {
                    PlayerView()
                        .environment(playback)
                        // The player grows out of the control that opened it and shrinks back into it.
                        .navigationTransition(.zoom(sourceID: playback.zoomSource ?? "", in: playerZoom))
                        // The player's own swipe down turns iPhone upright before closing; the zoom's built-in
                        // swipe would shrink it over a sideways screen.
                        .interactiveDismissDisabled()
                }
        #else
            content
                .sheet(isPresented: $playback.isPlayerPresented) {
                    PlayerView()
                        .environment(playback)
                }
        #endif
    }
}

/// The mini player for whatever is playing.
private struct NowPlayingAccessory: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        if let item = playback.nowPlaying {
            ItemArtwork(item, role: .landscape, width: 72) { artwork in
                MiniPlayer(
                    title: item.card.title,
                    subtitle: item.card.eyebrowText,
                    artwork: artwork,
                    isPlaying: playback.isPlaying,
                    playPause: { playback.togglePlayPause() },
                    close: { playback.stop() },
                    open: { playback.showPlayer() }
                )
                .modifier(MiniPlayerZoomSource())
            }
        }
    }
}

/// Makes the mini player the source of the player's zoom transition.
private struct MiniPlayerZoomSource: ViewModifier {
    @Environment(\.playerZoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            // A rounded rectangle as round as the bar is tall: the only shape transition sources accept.
            content.matchedTransitionSource(id: PlaybackCoordinator.miniPlayerZoomSource, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: 24, style: .continuous))
            }
        } else {
            content
        }
    }
}

#Preview("Light") {
    MainTabs()
}

#Preview("Dark") {
    MainTabs()
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    MainTabs()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Signed out") {
    RootView()
        .environment(AppSession.preview())
}
