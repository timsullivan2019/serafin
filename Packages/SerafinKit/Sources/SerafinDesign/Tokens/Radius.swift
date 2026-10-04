import SwiftUI

/// Serafin's corner radius scale. Corners are always continuous, never plain circular arcs.
public enum Radius: CGFloat, CaseIterable, Sendable {
    /// 12 pt, for posters, thumbnails and chips.
    case small = 12
    /// 16 pt, for larger cards and panels.
    case medium = 16
    /// 24 pt, for floating glass such as the player controls.
    case large = 24
}

extension Shape where Self == RoundedRectangle {
    /// A rectangle with continuous corners from Serafin's radius scale.
    ///
    /// Use it anywhere SwiftUI takes a shape:
    ///
    ///     poster.clipShape(.rounded(.small))
    ///     controls.glassEffect(.regular, in: .rounded(.large))
    ///
    /// - Parameter radius: The corner radius from the scale.
    public static func rounded(_ radius: Radius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius.rawValue, style: .continuous)
    }
}
