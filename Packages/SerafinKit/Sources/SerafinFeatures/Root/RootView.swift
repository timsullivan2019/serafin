import SerafinDesign
import SwiftUI

/// The root of Serafin's interface: Home, Library, Search and Settings tabs, a sidebar on iPad, and the mini player
/// in the tab bar while something plays.
public struct RootView: View {
    @State private var selection = AppTab.home
    @State private var playback = PlaybackCoordinator()

    /// Creates the root view.
    public init() {}

    public var body: some View {
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
        .tint(.accentFallback)
        .modifier(TabChrome(playback: playback))
        .environment(playback)
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
        if let card = playback.nowPlaying {
            MiniPlayer(
                title: card.title,
                subtitle: card.eyebrowText,
                artwork: Catalog.backdrop(for: card),
                isPlaying: playback.isPlaying,
                playPause: { playback.togglePlayPause() },
                close: { playback.stop() },
                open: { playback.showPlayer() }
            )
        }
    }
}

#Preview("Light") {
    RootView()
}

#Preview("Dark") {
    RootView()
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    RootView()
        .dynamicTypeSize(.accessibility5)
}
