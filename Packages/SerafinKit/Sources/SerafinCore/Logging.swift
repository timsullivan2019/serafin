import os

extension Logger {
    /// The unified logging subsystem shared by every Serafin module. It matches the app's bundle identifier.
    public static let serafinSubsystem = "app.getserafin.serafin"

    /// Creates a logger for one area of Serafin, such as `"auth"` or `"playback"`, under ``serafinSubsystem``.
    ///
    /// Log every URL, token, username, server name and item title with `privacy: .private`.
    ///
    /// - Parameter category: The area of the app the messages come from.
    public init(serafinCategory category: String) {
        self.init(subsystem: Self.serafinSubsystem, category: category)
    }
}
