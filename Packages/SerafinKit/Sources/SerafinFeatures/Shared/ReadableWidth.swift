import SerafinDesign
import SwiftUI

extension View {
    /// Keeps a form or list at a comfortable width on wide screens, centring it the way Settings does on iPad. On
    /// narrower screens the form keeps its usual margins.
    func readableWidth(_ maxWidth: CGFloat = 620) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            // Content margins replace the form's own, so they are set only when they are wider than those.
            if width > maxWidth + 2 * Spacing.large {
                content.contentMargins(.horizontal, (width - maxWidth) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }
}
