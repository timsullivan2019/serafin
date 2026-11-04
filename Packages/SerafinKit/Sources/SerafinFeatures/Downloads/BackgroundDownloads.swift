import SerafinCore

/// What the app delegate needs when iOS relaunches Serafin for its downloads.
public enum BackgroundDownloads {
    /// Waits until the downloads' background session named `identifier` has delivered its events, so finished files
    /// are saved before iOS suspends the app again. Returns at once for any other session.
    public static func eventsDelivered(forSession identifier: String) async {
        guard identifier == DownloadTransfers.backgroundIdentifier else { return }
        await DownloadTransfers.backgroundEventsDelivered()
    }
}
