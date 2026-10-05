import Observation
import SerafinCore

/// What Siri, Shortcuts and Spotlight have asked Serafin to show or play, held until the tabs can do it.
///
/// A request can arrive while the app is still starting, or while the app lock is up, so it waits here. The tabs act
/// on it once they show and the lock is down.
@Observable @MainActor public final class AppRequests {
    /// Something to show or play.
    public enum Request: Hashable, Sendable {
        /// Show an item's page.
        case show(itemID: String)
        /// Play a movie or episode where the user left off, or a show's next episode.
        case play(itemID: String)
        /// Show search results for a term.
        case search(String)
    }

    /// The request waiting for the tabs, or nil. A newer request replaces one that hasn't been acted on.
    public private(set) var pending: Request?

    /// Creates an empty queue.
    public init() {}

    /// Asks the tabs to show or play something. A request for an item whose ID Jellyfin wouldn't issue is dropped.
    public func send(_ request: Request) {
        switch request {
        case .show(let id), .play(let id):
            guard ItemID.isPlain(id) else { return }
        case .search:
            break
        }
        pending = request
    }

    /// The waiting request, which no longer waits, so it's acted on once.
    func take() -> Request? {
        defer { pending = nil }
        return pending
    }
}
