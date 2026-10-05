import Foundation
import SerafinPlayback

extension SubtitleStyle {
    /// Where the subtitle size is saved.
    static let sizeKey = "app.getserafin.serafin.subtitles.size"

    /// The style picked in Settings, or the standard style.
    static func saved(in defaults: UserDefaults) -> SubtitleStyle {
        SubtitleStyle(size: defaults.string(forKey: sizeKey).flatMap(Size.init) ?? .standard)
    }

    /// Keeps the style for the next launch.
    func save(in defaults: UserDefaults) {
        defaults.set(size.rawValue, forKey: Self.sizeKey)
    }
}

extension SubtitleStyle.Size: Identifiable {
    public var id: Self { self }

    /// The size as Settings lists it.
    var title: String {
        switch self {
        case .standard:
            String(localized: "Standard", bundle: .module, comment: "Subtitle size: the system caption style's own.")
        case .small:
            String(localized: "Small", bundle: .module, comment: "Subtitle size.")
        case .large:
            String(localized: "Large", bundle: .module, comment: "Subtitle size.")
        case .extraLarge:
            String(localized: "Extra Large", bundle: .module, comment: "Subtitle size.")
        }
    }
}
