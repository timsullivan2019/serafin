import SwiftUI

/// The signed-in user's picture in a circle, or their initial on the accent colour when they have none, for the
/// profile button in the root screens' toolbars.
public struct ProfileAvatar: View {
    private let name: String
    private let image: Image?
    private let size: CGFloat
    @Environment(\.accent) private var accent

    /// Creates an avatar.
    ///
    /// - Parameters:
    ///   - name: The user's name, whose first letter stands in for a picture.
    ///   - image: The user's picture, or nil for none or while it loads.
    ///   - size: The circle's diameter, in points.
    public init(name: String, image: Image?, size: CGFloat = 28) {
        self.name = name
        self.image = image
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(accent)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeOut(duration: 0.25), value: image != nil)
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    /// The first letter of the name, or a question mark for an empty one.
    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

#if DEBUG
    private struct ProfileAvatarSample: View {
        var body: some View {
            HStack(spacing: Spacing.large) {
                ProfileAvatar(name: "Alice", image: nil)
                ProfileAvatar(name: "Alice", image: MockMedia.posterImage(for: MockMedia.movies[3]))
                ProfileAvatar(name: "bram", image: nil, size: 44)
            }
            .padding()
            .background(Color.background)
        }
    }

    #Preview("Light") {
        ProfileAvatarSample()
    }

    #Preview("Dark") {
        ProfileAvatarSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ProfileAvatarSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
