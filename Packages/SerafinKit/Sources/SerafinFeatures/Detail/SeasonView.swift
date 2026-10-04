import SerafinDesign
import SwiftUI

/// A season's episodes as a grid of thumbnails.
struct SeasonView: View {
    let id: String
    @Environment(\.zoomNamespace) private var zoom
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 300.0

    var body: some View {
        Group {
            if let season = Catalog.season(id: id) {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.medium, alignment: .top)],
                        spacing: Spacing.large
                    ) {
                        ForEach(season.episodes) { episode in
                            LandscapeLink(card: episode)
                        }
                    }
                    .padding(Spacing.medium)
                }
                .navigationTitle(season.title)
                .navigationSubtitle(Catalog.series(id: season.seriesID)?.title ?? "")
            } else {
                ErrorState(
                    String(
                        localized: "Can't Find This Season", bundle: .module, comment: "Title when a season is missing."
                    ),
                    systemImage: "questionmark.square.dashed"
                )
            }
        }
        .background(Color.background)
        .zoomTransition(from: id, in: zoom)
    }
}

#Preview("Light") {
    TabStack { SeasonView(id: "series-sherlock-holmes-s1") }
        .environment(PlaybackCoordinator())
}

#Preview("Dark") {
    TabStack { SeasonView(id: "series-sherlock-holmes-s2") }
        .environment(PlaybackCoordinator())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { SeasonView(id: "series-alice-s1") }
        .environment(PlaybackCoordinator())
        .dynamicTypeSize(.accessibility5)
}
