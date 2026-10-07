import SwiftUI

/// A user on a server's sign-in screen: their picture, or their initial on the accent colour, above their name, as
/// Jellyfin's own web app lists them. The chosen user is ringed in the accent colour.
///
/// Wrap it in a `Button` that fills in the name.
public struct UserTile: View {
    private let name: String
    private let image: Image?
    private let isSelected: Bool
    @ScaledMetric(relativeTo: .body) private var size = 64.0
    @Environment(\.accent) private var accent

    /// Creates a tile.
    ///
    /// - Parameters:
    ///   - name: The user's name.
    ///   - image: The user's picture, or nil while it loads or when they have none.
    ///   - isSelected: Whether this user's name is the one filled in.
    public init(name: String, image: Image?, isSelected: Bool) {
        self.name = name
        self.image = image
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(spacing: Spacing.xSmall) {
            ProfileAvatar(name: name, image: image, size: size)
                .padding(4)
                .overlay {
                    Circle()
                        .strokeBorder(accent, lineWidth: 2.5)
                        .opacity(isSelected ? 1 : 0)
                }
            Text(name)
                .typography(.caption)
                .foregroundStyle(isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)
        }
        .frame(minWidth: size + Spacing.large)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
    private struct UserTileSample: View {
        var body: some View {
            HStack(alignment: .top, spacing: Spacing.medium) {
                UserTile(name: "Alice", image: MockMedia.posterImage(for: MockMedia.movies[3]), isSelected: true)
                UserTile(name: "Bram", image: nil, isSelected: false)
                UserTile(name: "Kids", image: nil, isSelected: false)
            }
            .padding()
            .background(Color.background)
        }
    }

    #Preview("Light") {
        UserTileSample()
    }

    #Preview("Dark") {
        UserTileSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        UserTileSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
