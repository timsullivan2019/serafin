import SerafinDesign
import SwiftUI

/// A movie, series or episode: the hero header, the overview, then seasons, episodes or suggestions.
struct ItemDetailView: View {
    @State private var model: ItemDetailModel
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.zoomNamespace) private var zoom

    init(id: String) {
        _model = State(initialValue: ItemDetailModel(id: id))
    }

    var body: some View {
        Group {
            if let card = model.card {
                details(for: card)
            } else {
                ErrorState(
                    String(
                        localized: "Can't Find This Item", bundle: .module, comment: "Title when an item is missing."),
                    message: String(
                        localized: "It may have been removed from your library.",
                        bundle: .module,
                        comment: "Explanation when an item is missing."
                    ),
                    systemImage: "questionmark.square.dashed"
                )
            }
        }
        .background(Color.background)
        .zoomTransition(from: model.id, in: zoom)
    }

    private func details(for card: MediaCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                HeroHeader(card: card, backdrop: Catalog.backdrop(for: card), tint: model.tint) {
                    playback.play(Catalog.playable(for: card))
                }
                if let overview = model.overview {
                    Text(overview)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, Spacing.medium)
                }
                if !model.seasons.isEmpty {
                    MediaRow(
                        String(localized: "Seasons", bundle: .module, comment: "Row of a series' seasons."),
                        style: .posters,
                        items: model.seasons.map(\.card)
                    ) { PosterLink(card: $0) }
                }
                if !model.seasonEpisodes.isEmpty {
                    MediaRow(
                        String(localized: "More Episodes", bundle: .module, comment: "Row of other episodes."),
                        style: .landscape,
                        items: model.seasonEpisodes
                    ) { LandscapeLink(card: $0) }
                }
                if !model.moreLike.isEmpty {
                    MediaRow(
                        String(localized: "More Like This", bundle: .module, comment: "Row of suggestions."),
                        style: .posters,
                        items: model.moreLike
                    ) { PosterLink(card: $0) }
                }
            }
            .padding(.bottom, Spacing.xLarge)
        }
        // The hero runs under the navigation bar, whose glass back button floats over the artwork.
        .ignoresSafeArea(edges: .top)
    }
}

#Preview("Movie") {
    TabStack { ItemDetailView(id: "movie-sintel") }
        .environment(PlaybackCoordinator())
}

#Preview("Series, dark") {
    TabStack { ItemDetailView(id: "series-sherlock-holmes") }
        .environment(PlaybackCoordinator())
        .preferredColorScheme(.dark)
}

#Preview("Episode, largest text") {
    TabStack { ItemDetailView(id: "series-caminandes-s1e2") }
        .environment(PlaybackCoordinator())
        .dynamicTypeSize(.accessibility5)
}
