#if DEBUG
    import SwiftUI

    /// Every SerafinDesign component on one screen, built from the mock fixtures, for the owner's review.
    public struct ComponentGallery: View {
        /// Creates the gallery.
        public init() {}

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xLarge) {
                    HeroHeader(
                        card: MockMedia.movies[1],
                        backdrop: MockMedia.backdropImage(for: MockMedia.movies[1]),
                        tint: MockMedia.tint(for: MockMedia.movies[1])
                    ) {}
                    GallerySection("MediaRow · LandscapeCard") {
                        MediaRow(
                            "Continue Watching",
                            style: .landscape,
                            items: MockLibrary.continueWatching
                        ) { card in
                            Button {
                            } label: {
                                LandscapeCard(card: card, artwork: MockMedia.backdropImage(for: card)) {
                                    PreviewMenuItems()
                                }
                            }
                            .buttonStyle(.card)
                        }
                    }
                    GallerySection("MediaRow · PosterCard") {
                        MediaRow("Movies", style: .posters, items: MockMedia.movies, seeAll: {}) { card in
                            Button {
                            } label: {
                                PosterCard(card: card, artwork: MockMedia.posterImage(for: card)) {
                                    PreviewMenuItems()
                                }
                            }
                            .buttonStyle(.card)
                        }
                    }
                    GallerySection("GlassChip") { GalleryChips() }
                    GallerySection("PlayerControls") { GalleryPlayer() }
                    GallerySection("EmptyState · ErrorState · LoadingState") { GalleryStates() }
                }
                .padding(.bottom, Spacing.xLarge)
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.background)
        }
    }

    /// A labelled block in the gallery.
    private struct GallerySection<Content: View>: View {
        let title: String
        let content: Content

        init(_ title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(verbatim: title)
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Spacing.medium)
                content
            }
        }
    }

    private struct GalleryChips: View {
        @State private var sort = "Name"
        @State private var unplayedOnly = false

        var body: some View {
            ScrollView(.horizontal) {
                GlassChipGroup {
                    GlassChip("Unplayed", systemImage: "circle.dashed", isSelected: unplayedOnly) {
                        unplayedOnly.toggle()
                    }
                    ForEach(["Name", "Date Added", "Year", "Rating"], id: \.self) { option in
                        GlassChip(option, isSelected: sort == option) { sort = option }
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
            }
            .scrollIndicators(.hidden)
            .background {
                // Glass needs something to refract, so the chips float over artwork here as they will in Library.
                (MockMedia.backdropImage(for: MockMedia.movies[4]) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
        }
    }

    private struct GalleryPlayer: View {
        @State private var isPlaying = true
        private let card = MockMedia.movies[11]

        var body: some View {
            PlayerControls(
                title: card.title,
                subtitle: card.year.map(String.init),
                status: PlayerControlsStatus(
                    isPlaying: isPlaying,
                    elapsed: .seconds(1356),
                    duration: card.runtime ?? .seconds(6780),
                    buffered: .seconds(1800)
                ),
                fillsScreen: false,
                actions: PlayerControlActions(playPause: { isPlaying.toggle() })
            ) {
                Image(systemName: "airplay.video")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(height: 420)
            .background {
                (MockMedia.backdropImage(for: card) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(.rounded(.large))
            .padding(.horizontal, Spacing.medium)
        }
    }

    private struct GalleryStates: View {
        var body: some View {
            VStack(spacing: Spacing.medium) {
                EmptyState(
                    "No Unplayed Movies",
                    message: "Everything in this library has been watched.",
                    systemImage: "film.stack",
                    action: StateAction("Clear Filter") {}
                )
                ErrorState(
                    "Can't Reach Your Server",
                    message: "Check that your Jellyfin server is running.",
                    systemImage: "wifi.exclamationmark",
                    retry: {}
                )
                LoadingState("Loading your library")
                    .frame(height: 140)
            }
            .background(.surface, in: .rounded(.medium))
            .padding(.horizontal, Spacing.medium)
        }
    }

    #Preview("Light") {
        ComponentGallery()
    }

    #Preview("Dark") {
        ComponentGallery()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ComponentGallery()
            .dynamicTypeSize(.accessibility5)
    }
#endif
