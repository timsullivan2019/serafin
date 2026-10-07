import SerafinDesign
import SwiftUI

/// The genres of every library, each opening a grid of its movies and shows, with two of its posters and how many
/// there are.
struct GenresView: View {
    @State private var model = GenresModel()
    @Environment(\.media) private var media

    var body: some View {
        content
            .navigationTitle(String(localized: "Genres", bundle: .module, comment: "Genres, as a heading or a label."))
            .task { await model.load(from: media) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            LoadingState()
        case .failed(let message):
            FailureState(message: message) { Task { await model.load(from: media) } }
        case .loaded(let genres) where genres.isEmpty:
            EmptyState(
                String(localized: "No Genres", bundle: .module, comment: "Title when the server lists no genres."),
                message: String(
                    localized:
                        "Genres appear here once your server has matched your movies and shows to their details.",
                    bundle: .module,
                    comment: "Explanation when the server lists no genres."
                ),
                systemImage: "theatermasks"
            )
        case .loaded(let genres):
            List(genres) { genre in
                NavigationLink(value: Route.genre(genre)) {
                    LabeledContent {
                        if let count = genre.count {
                            Text(count, format: .number)
                                .accessibilityLabel(
                                    String(
                                        localized: "\(count) titles", bundle: .module,
                                        comment: "Spoken count of a genre's movies and shows, such as 18 titles.")
                                )
                        }
                    } label: {
                        HStack(spacing: Spacing.small) {
                            GenreThumbnail(genre: genre)
                            Text(genre.name)
                        }
                    }
                }
            }
            .refreshable {
                await media.refresh()
                await model.load(from: media)
            }
        }
    }
}

/// Two of a genre's posters side by side in a small rounded square, loaded when the row comes on screen.
private struct GenreThumbnail: View {
    let genre: Genre
    @State private var posters: [MediaItem] = []
    @Environment(\.media) private var media
    @ScaledMetric(relativeTo: .body) private var size = 36.0

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<2, id: \.self) { index in
                Color.clear
                    .overlay {
                        if posters.indices.contains(index) {
                            ItemArtwork(posters[index], role: .poster) { CollagePoster(image: $0) }
                        } else {
                            CollagePoster(image: nil)
                        }
                    }
                    .clipped()
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
        .task(id: genre) {
            let page = try? await media.page(of: .genre(genre), options: GridOptions(), start: 0, limit: 2)
            posters = page?.items.compactMap { $0 } ?? []
        }
    }
}

#if DEBUG
    #Preview("Light") {
        TabStack { GenresView() }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { GenresView() }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { GenresView() }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
