import SerafinDesign
import SwiftUI

/// Continue Watching or Next Up on a screen of its own, from the chevron on Home's row: every item as a grid of
/// thumbnails.
struct WatchListView: View {
    @State private var model: WatchListModel
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 300.0

    init(list: WatchList) {
        _model = State(initialValue: WatchListModel(list: list))
    }

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(model.list.title)
            .task(id: actions.revision) { await model.load(from: media) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.thumbnailGrid(columnMinimum: columnWidth))
        case .failed(let message):
            FailureState(message: message) { Task { await model.load(from: media) } }
        case .loaded(let items) where items.isEmpty:
            EmptyState(
                model.list.emptyTitle,
                message: model.list.emptyMessage,
                systemImage: model.list.systemImage
            )
        case .loaded(let items):
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.medium, alignment: .top)],
                    spacing: Spacing.large
                ) {
                    ForEach(items) { item in
                        LandscapeLink(item: item, showsPlayedBadge: model.list != .continueWatching, role: .watching)
                    }
                }
                .padding(Spacing.medium)
            }
            .refreshable {
                await media.refresh()
                await model.load(from: media)
            }
        }
    }
}

/// One of Home's lists of things to watch.
enum WatchList: Hashable {
    /// Started movies and episodes.
    case continueWatching
    /// The next episode of each show in progress.
    case nextUp

    /// The screen's title, the same as the row's.
    var title: String {
        switch self {
        case .continueWatching:
            String(
                localized: "Continue Watching", bundle: .module,
                comment: "Started movies and episodes: the Home row, and the shortcut that plays the latest of them.")
        case .nextUp:
            String(localized: "Next Up", bundle: .module, comment: "Home row of next episodes.")
        }
    }

    var emptyTitle: String {
        switch self {
        case .continueWatching:
            String(
                localized: "Nothing Started", bundle: .module,
                comment: "Title when Continue Watching's screen has nothing in it.")
        case .nextUp:
            String(
                localized: "No Next Episodes", bundle: .module,
                comment: "Title when Next Up's screen has nothing in it."
            )
        }
    }

    var emptyMessage: String {
        switch self {
        case .continueWatching:
            String(
                localized: "Movies and episodes you start appear here until you finish them.", bundle: .module,
                comment: "Explanation when Continue Watching's screen has nothing in it.")
        case .nextUp:
            String(
                localized: "The next episode of each show you're watching appears here.", bundle: .module,
                comment: "Explanation when Next Up's screen has nothing in it.")
        }
    }

    var systemImage: String {
        switch self {
        case .continueWatching: "play.circle"
        case .nextUp: "tv"
        }
    }
}

/// The items of one of Home's lists.
@Observable @MainActor final class WatchListModel {
    enum Phase {
        case loading
        case loaded([MediaItem])
        case failed(UserMessage)
    }

    let list: WatchList
    private(set) var phase = Phase.loading

    init(list: WatchList) {
        self.list = list
    }

    /// Loads the list. A failed reload keeps the items already showing.
    func load(from media: any MediaSource) async {
        do {
            switch list {
            case .continueWatching: phase = .loaded(try await media.continueWatching())
            case .nextUp: phase = .loaded(try await media.nextUp())
            }
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }
}

#if DEBUG
    #Preview("Light") {
        TabStack { WatchListView(list: .continueWatching) }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { WatchListView(list: .nextUp) }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { WatchListView(list: .continueWatching) }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
