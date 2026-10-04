import SwiftUI

// Serafin's semantic colours. Each one resolves for light and dark appearance from `Theme.xcassets` in this
// module's resources, so values can be tuned in Xcode's colour editor without touching code.

extension Color {
    /// The screen background behind all content: white in light appearance, black in dark.
    ///
    /// Write it as `Color.background`. A bare `.background` where SwiftUI expects a shape style resolves to
    /// SwiftUI's own `BackgroundStyle` instead.
    public static let background = Color("Background", bundle: .module)
}

extension ShapeStyle where Self == Color {
    /// Grouped content that sits on ``SwiftUICore/Color/background``, such as settings rows and state panels.
    public static var surface: Color { Color("Surface", bundle: .module) }

    /// Titles and body text. Meets 4.5:1 contrast on the background and on ``surface`` in both appearances.
    public static var textPrimary: Color { Color("TextPrimary", bundle: .module) }

    /// Metadata such as year, runtime and episode codes. Meets 4.5:1 contrast on the background and on
    /// ``surface`` in both appearances.
    public static var textSecondary: Color { Color("TextSecondary", bundle: .module) }

    /// The glass tint for screens whose artwork gives no colour, a violet blue from the family of Jellyfin's
    /// gradient. Like every ``ArtworkTint`` result, it is dark enough for white text at 4.5:1 contrast.
    public static var accentFallback: Color { Color("AccentFallback", bundle: .module) }
}
