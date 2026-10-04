import Observation

/// A season's episodes.
@Observable @MainActor final class SeasonModel {
    enum Phase {
        case loading
        case loaded(SeasonContent)
        case failed(UserMessage)
    }

    let id: String
    let seriesID: String
    private(set) var phase = Phase.loading

    init(id: String, seriesID: String) {
        self.id = id
        self.seriesID = seriesID
    }

    /// Loads the episodes. A failed reload keeps the episodes already showing.
    func load(from media: any MediaSource) async {
        do {
            phase = .loaded(try await media.season(id, of: seriesID))
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }
}
