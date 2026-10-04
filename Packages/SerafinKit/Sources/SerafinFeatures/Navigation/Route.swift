import SwiftUI

/// A screen pushed onto a tab's navigation stack.
enum Route: Hashable {
    /// A movie, series or episode.
    case item(id: String)
    /// One library's full grid.
    case library(id: String)
    /// A season's episodes.
    case season(id: String)
    /// A person's filmography. Reserved for person pages after 1.0; nothing navigates here yet.
    case person(id: String)
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

    /// Pushes a route onto the current tab's navigation stack.
    @Entry var navigate = NavigateAction { _ in }
}

/// One tab's navigation stack, with every route registered and its own zoom namespace.
struct TabStack<Root: View>: View {
    @Namespace private var zoom
    @State private var path: [Route] = []
    private let root: Root

    init(@ViewBuilder root: () -> Root) {
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route)
                }
        }
        .environment(\.zoomNamespace, zoom)
        .environment(\.navigate, NavigateAction { [$path] route in $path.wrappedValue.append(route) })
    }
}

/// The screen for a route.
private struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .item(let id):
            ItemDetailView(id: id)
        case .library(let id):
            LibraryView(id: id)
        case .season(let id):
            SeasonView(id: id)
        case .person:
            EmptyView()
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
