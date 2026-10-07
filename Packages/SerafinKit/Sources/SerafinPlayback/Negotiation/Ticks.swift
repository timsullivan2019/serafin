/// Jellyfin measures time in ticks of 100 nanoseconds: ten million to the second.
public enum Ticks {
    /// Ticks in one second.
    public static let perSecond = 10_000_000

    /// `duration` in ticks, rounded down to a whole tick.
    public static func from(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * perSecond + Int(attoseconds / 100_000_000_000)
    }

    /// `ticks` as a duration.
    public static func duration(_ ticks: Int) -> Duration {
        .nanoseconds(Int64(ticks) * 100)
    }
}
