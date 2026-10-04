import SwiftUI

extension Animation {
    /// Serafin's default animation: the system snappy spring, 0.5 seconds with a little bounce.
    public static let serafinSnappy: Animation = .spring(.snappy)
}

/// Animation choices that respect the Reduce Motion accessibility setting.
///
/// The system tones down its own glass and navigation motion under Reduce Motion, but never the animations an
/// app writes itself. Route every custom animation through ``animation(_:reduceMotion:)`` or
/// ``SwiftUICore/View/serafinAnimation(value:)``.
public enum Motion {
    /// The animation Serafin uses instead when Reduce Motion is on: a short ease-out with no bounce, so state
    /// changes still read without travel or overshoot.
    public static let reduced: Animation = .easeOut(duration: 0.15)

    /// Returns the animation to use for a state change.
    ///
    ///     withAnimation(Motion.animation(reduceMotion: reduceMotion)) { isExpanded.toggle() }
    ///
    /// - Parameters:
    ///   - animation: The animation to use when Reduce Motion is off.
    ///   - reduceMotion: The value of `accessibilityReduceMotion` from the environment.
    /// - Returns: `animation`, or ``reduced`` when Reduce Motion is on.
    public static func animation(_ animation: Animation = .serafinSnappy, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

extension View {
    /// Animates changes to `value` with ``SwiftUICore/Animation/serafinSnappy``, or with ``Motion/reduced``
    /// when Reduce Motion is on.
    ///
    /// - Parameter value: The value whose changes animate.
    public func serafinAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(SerafinAnimationModifier(value: value))
    }
}

private struct SerafinAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.animation(reduceMotion: reduceMotion), value: value)
    }
}
