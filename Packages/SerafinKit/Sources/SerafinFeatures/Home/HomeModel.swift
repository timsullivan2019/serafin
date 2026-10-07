import Foundation
import Observation
import SerafinCore
import SerafinDesign

/// The rows of the home screen.
@Observable @MainActor final class HomeModel {
    enum Phase {
        case loading
        case loaded(HomeContent)
        case failed(UserMessage)
    }

    /// Why the rows showing may be out of date: the last load failed, and they're from ``date``.
    struct Notice: Equatable {
        /// What went wrong.
        let message: UserMessage
        /// When the server sent the rows showing.
        let date: Date
    }

    private(set) var phase = Phase.loading {
        didSet {
            // The hero picks in the same change as the rows, so they never show without it.
            guard case .loaded(let home) = phase else { return }
            hero.update(from: home) { [artwork] in HomeHeroPage.hasArtwork($0, artwork: artwork) }
            revision += 1
        }
    }
    /// Goes up each time new rows show, so the hero's shows look up their episodes again.
    private(set) var revision = 0
    /// The featured items at the top.
    let hero = HomeHeroModel()
    /// Where artwork loads from, for skipping items the hero can't draw. Nil with the samples.
    var artwork: Artwork?
    /// Set when a load fails while rows are showing, and cleared when one succeeds.
    private(set) var notice: Notice?
    /// How many loads are running. Pull to refresh can run one beside another.
    private var loads = 0

    /// Whether the rows are being asked for.
    var isLoading: Bool { loads > 0 }

    /// Whether the last load failed, leaving a failure or out-of-date rows on screen, so it's worth asking again when
    /// the device joins a network or Serafin comes back to the foreground.
    var isWorthRetrying: Bool {
        if notice != nil { return true }
        if case .failed = phase { return true }
        return false
    }

    /// Loads the rows. The first load shows the rows saved on the device straight away, if there are any, while it
    /// asks the server. A load that fails keeps the rows showing, with a notice saying why and when they're from.
    func load(from media: any MediaSource) async {
        loads += 1
        defer { loads -= 1 }
        if case .loading = phase, let saved = await media.savedHome(), case .loading = phase {
            phase = .loaded(saved)
        }
        do {
            phase = .loaded(try await media.home())
            notice = nil
        } catch is CancellationError {
        } catch {
            let message = UserMessage(error)
            if case .loaded(let home) = phase, !home.isEmpty {
                notice = Notice(message: message, date: home.date)
            } else {
                phase = .failed(message)
            }
        }
    }

    /// Asks the server again, skipping the cache, for pull to refresh.
    func refresh(from media: any MediaSource) async {
        await media.refresh()
        await load(from: media)
    }
}
