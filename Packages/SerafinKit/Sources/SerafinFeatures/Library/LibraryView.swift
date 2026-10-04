import SerafinDesign
import SwiftUI

/// The Library tab: the user's libraries, each opening its grid.
struct LibrariesView: View {
    var body: some View {
        List(Catalog.libraries) { library in
            NavigationLink(value: Route.library(id: library.id)) {
                Label {
                    LabeledContent(library.name) {
                        Text(library.items.count, format: .number)
                    }
                } icon: {
                    Image(systemName: library.kind == .movies ? "film" : "tv")
                }
            }
        }
        .navigationTitle(String(localized: "Library", bundle: .module, comment: "Title of the library tab."))
    }
}

/// One library as a poster grid, with glass chips for sorting and filtering floating over it.
struct LibraryView: View {
    @State private var model: LibraryModel
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 104.0

    init(id: String) {
        _model = State(initialValue: LibraryModel(id: id))
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                LibraryChips(model: model)
            }
            .background(Color.background)
            .navigationTitle(model.library?.name ?? "")
    }

    @ViewBuilder private var content: some View {
        if model.items.isEmpty {
            EmptyState(
                String(
                    localized: "No Unplayed Items", bundle: .module, comment: "Title when a filtered library is empty."),
                message: String(
                    localized: "Everything here has been watched.",
                    bundle: .module,
                    comment: "Explanation when the unplayed filter hides everything."
                ),
                systemImage: "checkmark.circle",
                action: StateAction(
                    String(
                        localized: "Show All", bundle: .module, comment: "Button that turns off the unplayed filter.")
                ) { model.unplayedOnly = false }
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.small, alignment: .top)],
                    spacing: Spacing.large
                ) {
                    ForEach(model.items) { card in
                        PosterLink(card: card)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
            }
        }
    }
}

/// The sort and filter chips above a library grid.
private struct LibraryChips: View {
    @Bindable var model: LibraryModel

    var body: some View {
        ScrollView(.horizontal) {
            GlassChipGroup {
                GlassChip(
                    String(localized: "Unplayed", bundle: .module, comment: "Library filter: hide played items."),
                    systemImage: "circle.dashed",
                    isSelected: model.unplayedOnly
                ) { model.unplayedOnly.toggle() }
                ForEach(LibrarySort.allCases) { sort in
                    GlassChip(sort.title, isSelected: model.sort == sort) { model.sort = sort }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.xSmall)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview("Libraries") {
    TabStack { LibrariesView() }
        .environment(PlaybackCoordinator())
}

#Preview("Light") {
    TabStack { LibraryView(id: "library-movies") }
        .environment(PlaybackCoordinator())
}

#Preview("Dark") {
    TabStack { LibraryView(id: "library-movies") }
        .environment(PlaybackCoordinator())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { LibraryView(id: "library-shows") }
        .environment(PlaybackCoordinator())
        .dynamicTypeSize(.accessibility5)
}
