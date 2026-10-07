import SerafinDesign
import SwiftUI

/// A season's episodes as a grid of thumbnails.
struct SeasonView: View {
    @State private var model: SeasonModel
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(\.zoomNamespace) private var zoom
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 300.0

    init(id: String, seriesID: String) {
        _model = State(initialValue: SeasonModel(id: id, seriesID: seriesID))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                Skeleton(.thumbnailGrid(columnMinimum: columnWidth))
            case .failed(let message):
                FailureState(message: message) { Task { await model.load(from: media) } }
            case .loaded(let season):
                episodes(season)
            }
        }
        .background(Color.background)
        .zoomTransition(from: model.id, in: zoom)
        .task(id: actions.revision) { await model.load(from: media) }
    }

    private func episodes(_ season: SeasonContent) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.medium, alignment: .top)],
                spacing: Spacing.large
            ) {
                ForEach(season.episodes) { episode in
                    LandscapeLink(item: episode)
                }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle(season.title)
        .navigationSubtitle(season.seriesTitle)
    }
}

#if DEBUG
    #Preview("Light") {
        TabStack { SeasonView(id: "series-sherlock-holmes-s1", seriesID: "series-sherlock-holmes") }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { SeasonView(id: "series-sherlock-holmes-s2", seriesID: "series-sherlock-holmes") }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { SeasonView(id: "series-alice-s1", seriesID: "series-alice") }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
