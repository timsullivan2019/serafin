import SwiftUI

/// Serafin's named text styles.
///
/// Each style maps to a system Dynamic Type style, so text follows the user's preferred reading size all the
/// way to the largest accessibility sizes. Serafin uses the system font only.
public enum Typography: CaseIterable, Sendable {
    /// Hero titles on detail screens when the artwork has no logo. System large title, bold.
    case largeTitle
    /// Section and shelf headers, such as Continue Watching. System title 2, bold, the size Apple's TV and
    /// Music apps use for shelves.
    case title
    /// Row titles and emphasised labels. System headline.
    case headline
    /// Titles under posters and thumbnails, where a headline would wrap too soon. System subheadline, semibold.
    case cardTitle
    /// Overviews and other running text. System body.
    case body
    /// Metadata such as year, runtime and episode codes. System caption.
    case caption

    /// The system font for this style.
    public var font: Font {
        switch self {
        case .largeTitle: .largeTitle.bold()
        case .title: .title2.bold()
        case .headline: .headline
        case .cardTitle: .subheadline.weight(.semibold)
        case .body: .body
        case .caption: .caption
        }
    }
}

extension View {
    /// Sets the font of text in this view to one of Serafin's named text styles.
    ///
    /// - Parameter style: The text style to use.
    public func typography(_ style: Typography) -> some View {
        font(style.font)
    }
}
