import SerafinCore
import SerafinDesign
import SwiftUI

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable {
    /// A movie, series or episode.
    case item(id: String)
    /// One library's full grid.
    case library(MediaLibrary)
    /// The genres of every library.
    case genres
    /// The movies and shows in one genre.
    case genre(Genre)
    /// Every collection.
    case collections
    /// The movies and shows in one collection.
    case collection(id: String, title: String)
    /// A season's episodes. Jellyfin lists them under the show, so the route carries both.
    case season(id: String, seriesID: String)
    /// A person's filmography. Reserved for person pages after 1.0; nothing navigates here yet.
    case person(id: String)
    /// Adding another server, from Settings.
    case addServer
    /// Signing in to a saved server, from Settings or after adding one.
    case signIn(Server)
    /// The open-source licences, from Settings.
    case licences
    /// Audio and subtitle languages, and how subtitles look, from Settings.
    case audioAndSubtitles
}

/// Pushes a route onto the current tab's navigation stack, for buttons that are not navigation links.
struct NavigateAction: Sendable {
    fileprivate let push: @MainActor @Sendable (Route) -> Void

    /// Pushes `route`.
    @MainActor func callAsFunction(_ route: Route) {
        push(route)
    }
}

extension EnvironmentValues {
    /// The namespace that pairs cards with the screens they zoom into, one per tab.
    @Entry var zoomNamespace: Namespace.ID?

    /// The namespace that pairs the full-screen player with the controls it grows out of: the hero's play pill and
    /// the mini player.
    @Entry var playerZoomNamespace: Namespace.ID?

    /// The latest request for the search tab: Command-F asking for the field, or Siri for a term's results.
    @Entry var searchRequest = SearchRequest()

    /// Pushes a route onto the current tab's navigation stack.
    @Entry var navigate = NavigateAction { _ in }
}

/// A request for the search tab.
struct SearchRequest: Equatable {
    /// Goes up with each request, so asking twice still asks.
    var number = 0
    /// The term to show results for, or nil to put the cursor in the search field.
    var term: String?
}

/// One tab's navigation stack, with every route registered and its own zoom namespace.
struct TabStack<Root: View>: View {
    @Namespace private var zoom
    @State private var ownPath: [Route] = []
    private let sharedPath: Binding<[Route]>?
    private let root: Root

    /// Creates a stack.
    ///
    /// - Parameters:
    ///   - path: The screens pushed onto the root, which the tabs also push onto for Siri and Spotlight. Without it
    ///     the stack keeps its own, as in previews.
    ///   - root: The tab's first screen.
    init(path: Binding<[Route]>? = nil, @ViewBuilder root: () -> Root) {
        sharedPath = path
        self.root = root()
    }

    private var path: Binding<[Route]> {
        sharedPath ?? $ownPath
    }

    var body: some View {
        NavigationStack(path: path) {
            root
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(\.zoomNamespace, zoom)
        .environment(\.navigate, NavigateAction { [path] route in path.wrappedValue.append(route) })
    }
}

/// The screen for a route.
private struct RouteDestination: View {
    let route: Route
    @Environment(\.navigate) private var navigate

    var body: some View {
        switch route {
        case .item(let id):
            ItemDetailView(id: id)
        case .library(let library):
            LibraryView(scope: .library(library))
        case .genres:
            GenresView()
        case .genre(let genre):
            LibraryView(scope: .genre(genre))
        case .collections:
            LibraryView(scope: .collections)
        case .collection(let id, let title):
            LibraryView(scope: .collection(id: id, title: title))
        case .season(let id, let seriesID):
            SeasonView(id: id, seriesID: seriesID)
        case .person:
            EmptyView()
        case .addServer:
            AddServerView { server in navigate(.signIn(server)) }
        case .signIn(let server):
            SignInView(server: server)
        case .licences:
            LicencesView()
        case .audioAndSubtitles:
            AudioAndSubtitlesView()
        }
    }
}

extension View {
    /// Zooms this screen in from the card with `id`, when the tab has a zoom namespace. iOS only.
    func zoomTransition(from id: String, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomTransition(id: id, namespace: namespace))
    }
}

private struct ZoomTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        #if os(iOS)
            if let namespace {
                content.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                content
            }
        #else
            content
        #endif
    }
}
