/// Jellyfin measures time in ticks of 100 nanoseconds: ten million to the second.
public enum Ticks {
    /// Ticks in one second.
    public static let perSecond = 10_000_000

    /// `duration` in ticks, rounded down to a whole tick. A duration too long to count in ticks gives the most ticks
    /// there can be, or the fewest for a negative one, rather than overflowing.
    public static func from(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        let (whole, overflowed) = Int(seconds).multipliedReportingOverflow(by: perSecond)
        let (ticks, carried) = whole.addingReportingOverflow(Int(attoseconds / 100_000_000_000))
        guard !overflowed, !carried else { return duration < .zero ? .min : .max }
        return ticks
    }

    /// `ticks` as a duration, or zero for a negative count, which no length or position has. Whole seconds and the
    /// rest convert apart, so even the largest count a server could send can't overflow.
    public static func duration(_ ticks: Int) -> Duration {
        guard ticks > 0 else { return .zero }
        return .seconds(ticks / perSecond) + .nanoseconds(ticks % perSecond * 100)
    }
}
