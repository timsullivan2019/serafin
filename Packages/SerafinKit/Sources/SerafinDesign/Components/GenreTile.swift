import SwiftUI

/// A genre in the Library tab's Genres row: a 16:9 tile of the genre's newest artwork, usually a ``PosterPair``, with
/// its name over a fade at the bottom.
///
/// The tile sizes itself: 160 by 90 points on iPhone, 240 by 135 on iPad, and wider at accessibility text sizes so the
/// name still fits. Wrap it in a `Button` or `NavigationLink` with `.buttonStyle(.card)` for the press effect.
public struct GenreTile<Artwork: View>: View {
    private let name: String
    private let artwork: Artwork
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - name: The genre's name.
    ///   - artwork: The picture, filling the tile: two posters side by side, or one picture across the whole tile
    ///     when the genre has only one title.
    public init(name: String, @ViewBuilder artwork: () -> Artwork) {
        self.name = name
        self.artwork = artwork()
    }

    public var body: some View {
        let size = GenreTileLayout.size(
            isRegular: sizeClass == .regular, isLarge: dynamicTypeSize.isAccessibilitySize)
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                ZStack {
                    Rectangle().fill(.surface)
                    artwork
                }
            }
            .overlay {
                // Clear over the top half, then darkening quickly under the name to 70% at the edge, so white text
                // reads over the brightest posters.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.4),
                        .init(color: .black.opacity(0.45), location: 0.72),
                        .init(color: .black.opacity(0.7), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                Text(name)
                    .typography(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .padding(Spacing.xSmall)
            }
            .clipShape(.rounded(.small))
            .cardHoverEffect()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
    }
}

/// Two posters side by side, each filling its half of the space and cropped to fit, as a ``GenreTile`` shows a genre.
public struct PosterPair<Cell: View>: View {
    private let cell: (Int) -> Cell

    /// Creates a pair.
    ///
    /// - Parameter cell: Draws the poster in each of the two places, 0 at the leading edge, usually a
    ///   ``CollagePoster``.
    public init(@ViewBuilder cell: @escaping (Int) -> Cell) {
        self.cell = cell
    }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<2, id: \.self) { index in
                Color.clear
                    .overlay { cell(index) }
                    .clipped()
            }
        }
    }
}

/// How large a ``GenreTile`` is, for the tile and for the skeleton that stands in for its row.
enum GenreTileLayout {
    /// A 16:9 size: 160 points wide on iPhone and 240 on iPad, or 300 and 360 at accessibility text sizes, where a
    /// name in large type needs the room.
    static func size(isRegular: Bool, isLarge: Bool) -> CGSize {
        let width: CGFloat =
            switch (isRegular, isLarge) {
            case (false, false): 160
            case (false, true): 300
            case (true, false): 240
            case (true, true): 360
            }
        return CGSize(width: width, height: width * 9 / 16)
    }
}

/// One picture in a collage, such as a ``GenreTile``'s, filling its place and fading in when it arrives.
public struct CollagePoster: View {
    private let image: Image?

    /// Creates a place for a picture.
    ///
    /// - Parameter image: The picture, usually a poster, or nil while it loads.
    public init(image: Image?) {
        self.image = image
    }

    public var body: some View {
        ZStack {
            Rectangle().fill(.surface)
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
    }
}

#if DEBUG
    private struct GenreTileSample: View {
        /// Sample genres with the films whose art they show: two posters, one backdrop across the tile for a genre
        /// with a single film, and none for one still loading.
        private let genres: [(name: String, films: [String])] = [
            ("Animation", ["movie-sprite-fright", "movie-spring"]),
            ("Comedy", ["movie-his-girl-friday", "movie-the-general"]),
            ("Mystery", ["movie-charade"]),
            ("Science Fiction", ["movie-tears-of-steel", "movie-elephants-dream"]),
            ("Horror", []),
        ]

        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.small) {
                    ForEach(genres, id: \.name) { genre in
                        let films = genre.films.compactMap { id in MockMedia.movies.first { $0.id == id } }
                        GenreTile(name: genre.name) {
                            if films.count >= 2 {
                                PosterPair { index in CollagePoster(image: MockMedia.posterImage(for: films[index])) }
                            } else if let film = films.first {
                                CollagePoster(image: MockMedia.backdropImage(for: film))
                            } else {
                                CollagePoster(image: nil)
                            }
                        }
                    }
                }
            }
            .contentMargins(Spacing.medium, for: .scrollContent)
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            .background(Color.background)
        }
    }

    #Preview("Light") {
        GenreTileSample()
    }

    #Preview("Dark") {
        GenreTileSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        GenreTileSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
