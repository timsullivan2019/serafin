import SerafinDesign
import SwiftUI

/// The genres of every library, each opening a grid of its movies and shows, with how many there are.
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
                    LabeledContent(genre.name) {
                        if let count = genre.count {
                            Text(count, format: .number)
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
