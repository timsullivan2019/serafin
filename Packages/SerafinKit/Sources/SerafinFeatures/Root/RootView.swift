import SerafinCore
import SerafinDesign
import SerafinPlayback
import SwiftUI

/// The root of Serafin's interface: the connect flow until someone signs in, then the tabs, browsing as the
/// current account.
public struct RootView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppLock.self) private var lock: AppLock?

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
    }
}

/// Home, Library, Search and Settings tabs, a sidebar on iPad, and the mini player in the tab bar while something
/// plays.
struct MainTabs: View {
    @State private var selection = AppTab.home
    @State private var searchRequest = 0
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
                TabStack { HomeView() }
            }
            Tab(
                String(localized: "Library", bundle: .module, comment: "Title of the library tab."),
                systemImage: "square.grid.2x2",
                value: AppTab.library
            ) {
                TabStack { LibrariesView() }
            }
            Tab(
                String(localized: "Settings", bundle: .module, comment: "Title of the settings tab."),
                systemImage: "gearshape",
                value: AppTab.settings
            ) {
                TabStack { SettingsView() }
            }
            Tab(value: AppTab.search, role: .search) {
                TabStack { SearchView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background {
            TabShortcuts(selection: $selection, searchRequest: $searchRequest)
        }
        .environment(\.searchFocusRequest, searchRequest)
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
    @Binding var searchRequest: Int
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
                searchRequest += 1
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
