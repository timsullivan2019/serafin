import AVFoundation
import CoreMedia

/// How big text subtitles are.
///
/// The player applies it to subtitles it draws from text, such as WebVTT in an HLS stream. Subtitles the server burns
/// into the picture keep the size they came with. The rest of the look, such as the box behind the words, belongs to
/// the caption style chosen in the system's accessibility settings, which iOS doesn't let video change.
public struct SubtitleStyle: Hashable, Sendable {
    /// How big subtitles are.
    public enum Size: String, CaseIterable, Sendable {
        /// The size the system's caption style sets.
        case standard
        /// Three quarters of the standard size.
        case small
        /// A third bigger than standard.
        case large
        /// Two thirds bigger than standard.
        case extraLarge

        /// The size as a percentage of the standard size, or nil for the standard size.
        var percent: Int? {
            switch self {
            case .standard: nil
            case .small: 75
            case .large: 133
            case .extraLarge: 167
            }
        }
    }

    /// How big subtitles are.
    public var size: Size

    /// Creates a style.
    public init(size: Size = .standard) {
        self.size = size
    }

    /// The system's own caption style, unchanged.
    public static let standard = SubtitleStyle()

    /// The markup the player styles text subtitles with. Empty for the standard style.
    var textMarkupAttributes: [String: Any] {
        guard let percent = size.percent else { return [:] }
        return [kCMTextMarkupAttribute_RelativeFontSize as String: percent]
    }

    /// The rules the player styles text subtitles with. Empty for the standard style.
    var textStyleRules: [AVTextStyleRule] {
        let attributes = textMarkupAttributes
        guard !attributes.isEmpty, let rule = AVTextStyleRule(textMarkupAttributes: attributes) else { return [] }
        return [rule]
    }
}
