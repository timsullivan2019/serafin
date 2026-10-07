import SwiftUI

/// A library on the Library tab: a 16:9 picture with the library's name and how many titles it holds over a fade
/// at the bottom.
///
/// The picture is the library's own when the server has one, otherwise a ``LibraryCollage`` of its newest
/// posters. Wrap it in a `NavigationLink` with `.buttonStyle(.card)` for the press effect.
public struct LibraryTile<Artwork: View>: View {
    private let name: String
    private let caption: String?
    private let artwork: Artwork

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - name: The library's name.
    ///   - caption: How many titles it holds, such as "75 movies", or nil while that loads.
    ///   - artwork: The picture, filling a 16:9 frame.
    public init(name: String, caption: String?, @ViewBuilder artwork: () -> Artwork) {
        self.name = name
        self.caption = caption
        self.artwork = artwork()
    }

    public var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.surface)
                    artwork
                }
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.35),
                        .init(color: .black.opacity(0.7), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .typography(.headline)
                        .lineLimit(2)
                    if let caption {
                        Text(caption)
                            .typography(.caption)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                .padding(Spacing.small)
            }
            .clipShape(.rounded(.small))
            .cardHoverEffect()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([name, caption].compactMap { $0 }.joined(separator: ", "))
    }
}

/// Four posters in a two-by-two grid, each cropped to fill its quarter, for a library without a picture of its own.
public struct LibraryCollage<Cell: View>: View {
    private let cell: (Int) -> Cell

    /// Creates a collage.
    ///
    /// - Parameter cell: Draws the poster for each of the four places, numbered 0 to 3 across then down.
    public init(@ViewBuilder cell: @escaping (Int) -> Cell) {
        self.cell = cell
    }

    public var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                place(0)
                place(1)
            }
            GridRow {
                place(2)
                place(3)
            }
        }
    }

    private func place(_ index: Int) -> some View {
        Color.clear
            .overlay { cell(index) }
            .clipped()
    }
}

/// One poster in a ``LibraryCollage``, fading in when it arrives.
public struct CollagePoster: View {
    private let image: Image?

    /// Creates a place for a poster.
    ///
    /// - Parameter image: The poster, or nil while it loads or when there are fewer than four.
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

/// A white symbol on a rounded square of the accent colour, as iOS Settings marks its rows.
public struct AccentIcon: View {
    private let systemImage: String
    @ScaledMetric(relativeTo: .body) private var size = 29.0
    @Environment(\.accent) private var accent

    /// Creates an icon.
    ///
    /// - Parameter systemImage: The SF Symbol.
    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(accent, in: .rect(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

#if DEBUG
    private struct LibraryTileSample: View {
        var body: some View {
            List {
                Section {
                    Grid(horizontalSpacing: Spacing.small, verticalSpacing: Spacing.small) {
                        GridRow {
                            LibraryTile(name: "Movies", caption: "12 movies") {
                                LibraryCollage { index in
                                    CollagePoster(image: MockMedia.posterImage(for: MockMedia.movies[index]))
                                }
                            }
                            LibraryTile(name: "Shows", caption: "4 shows") {
                                MockMedia.backdropImage(for: MockMedia.series[0])?
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    Label {
                        Text(verbatim: "Genres")
                    } icon: {
                        AccentIcon(systemImage: "theatermasks.fill")
                    }
                    Label {
                        Text(verbatim: "Favourites")
                    } icon: {
                        AccentIcon(systemImage: "heart.fill")
                    }
                }
            }
        }
    }

    #Preview("Light") {
        LibraryTileSample()
    }

    #Preview("Dark") {
        LibraryTileSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        LibraryTileSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
