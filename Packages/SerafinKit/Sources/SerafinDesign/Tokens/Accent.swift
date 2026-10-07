import SwiftUI

/// A colour people can choose in Settings for Serafin's buttons, links, selections and tab bar, in place of the
/// default violet. Colours taken from artwork, such as a detail screen's tint, stay as they are.
///
/// Each colour resolves from `Theme.xcassets`, which `scripts/accents.py` writes. Every one is as readable as the
/// violet: dark enough for white text on it, readable as text on the background in light and dark, and stronger
/// still with Increase Contrast.
public enum Accent: String, CaseIterable, Identifiable, Sendable {
    case violet
    case indigo
    case blue
    case sky
    case cyan
    case teal
    case mint
    case green
    case olive
    case amber
    case orange
    case red
    case crimson
    case pink
    case magenta
    case purple
    case graphite

    /// Serafin's own violet, used until someone chooses another.
    public static let standard = Accent.violet

    /// Where the choice is kept in `UserDefaults`.
    public static let storageKey = "accentColour"

    public var id: String { rawValue }

    /// The colour, for the current appearance and contrast.
    public var color: Color {
        guard self != .violet else { return .accentFallback }
        return Color("Accent\(rawValue.prefix(1).uppercased())\(rawValue.dropFirst())", bundle: .module)
    }

    /// The colour's name, as Settings and VoiceOver say it.
    public var name: String {
        switch self {
        case .violet: String(localized: "Violet", bundle: .module, comment: "Accent colour.")
        case .indigo: String(localized: "Indigo", bundle: .module, comment: "Accent colour.")
        case .blue: String(localized: "Blue", bundle: .module, comment: "Accent colour.")
        case .sky: String(localized: "Sky", bundle: .module, comment: "Accent colour: a light, sky blue.")
        case .cyan: String(localized: "Cyan", bundle: .module, comment: "Accent colour.")
        case .teal: String(localized: "Teal", bundle: .module, comment: "Accent colour.")
        case .mint: String(localized: "Mint", bundle: .module, comment: "Accent colour: a blue-green.")
        case .green: String(localized: "Green", bundle: .module, comment: "Accent colour.")
        case .olive: String(localized: "Olive", bundle: .module, comment: "Accent colour: a yellow-green.")
        case .amber: String(localized: "Amber", bundle: .module, comment: "Accent colour: a deep golden yellow.")
        case .orange: String(localized: "Orange", bundle: .module, comment: "Accent colour.")
        case .red: String(localized: "Red", bundle: .module, comment: "Accent colour.")
        case .crimson: String(localized: "Crimson", bundle: .module, comment: "Accent colour: a deep pinkish red.")
        case .pink: String(localized: "Pink", bundle: .module, comment: "Accent colour.")
        case .magenta: String(localized: "Magenta", bundle: .module, comment: "Accent colour.")
        case .purple: String(localized: "Purple", bundle: .module, comment: "Accent colour.")
        case .graphite: String(localized: "Graphite", bundle: .module, comment: "Accent colour: a neutral grey.")
        }
    }
}

extension EnvironmentValues {
    /// The accent colour chosen in Settings, for controls that set their tint themselves rather than taking the
    /// screen's.
    @Entry public var accent: Color = .accentFallback
}

extension View {
    /// Builds this view afresh when the accent colour changes.
    ///
    /// Menu pickers and menus keep the tint they were first drawn with, so on a screen already showing, as Settings
    /// is while the colour is chosen, they need building again to take the new one.
    public func rebuiltForAccent() -> some View {
        modifier(AccentIdentity())
    }
}

private struct AccentIdentity: ViewModifier {
    @Environment(\.accent) private var accent

    func body(content: Content) -> some View {
        content.id(accent)
    }
}
