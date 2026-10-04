import Observation
import SerafinDesign

/// The rows of the home screen.
@Observable @MainActor final class HomeModel {
    enum Phase {
        case loading
        case loaded(HomeContent)
        case failed(UserMessage)
    }

    private(set) var phase = Phase.loading

    /// Loads the rows. A failed reload keeps the rows already showing.
    func load(from media: any MediaSource) async {
        do {
            phase = .loaded(try await media.home())
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }

    /// Asks the server again, skipping the cache, for pull to refresh.
    func refresh(from media: any MediaSource) async {
        await media.refresh()
        await load(from: media)
    }
}
