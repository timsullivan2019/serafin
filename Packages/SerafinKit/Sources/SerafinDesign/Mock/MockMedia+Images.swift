import SwiftUI

extension MockMedia {
    /// The generated poster for a card as a SwiftUI image, ready to pass to ``PosterCard``.
    ///
    /// - Parameter card: Any card.
    public static func posterImage(for card: MediaCard) -> Image? {
        poster(for: card).map { Image(decorative: $0, scale: 1) }
    }

    /// The generated backdrop for a card as a SwiftUI image, ready to pass to ``LandscapeCard`` or ``HeroHeader``.
    ///
    /// - Parameter card: Any card.
    public static func backdropImage(for card: MediaCard) -> Image? {
        backdrop(for: card).map { Image(decorative: $0, scale: 1) }
    }

    /// The glass tint ``ArtworkTint`` derives from a card's generated backdrop.
    ///
    /// - Parameter card: Any card.
    public static func tint(for card: MediaCard) -> Color {
        backdrop(for: card).map(ArtworkTint.color(for:)) ?? .accentFallback
    }
}

#if DEBUG
    /// Context menu items for previews, with fixed English labels that stay out of the string catalog.
    struct PreviewMenuItems: View {
        var body: some View {
            Button {
            } label: {
                Label {
                    Text(verbatim: "Play")
                } icon: {
                    Image(systemName: "play.fill")
                }
            }
            Button {
            } label: {
                Label {
                    Text(verbatim: "Mark as Played")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            Button {
            } label: {
                Label {
                    Text(verbatim: "Add to Favourites")
                } icon: {
                    Image(systemName: "heart")
                }
            }
        }
    }
#endif
