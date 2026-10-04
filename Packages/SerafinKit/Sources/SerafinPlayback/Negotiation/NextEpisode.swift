import JellyfinAPI
import SerafinCore

/// Finds the episode that follows another, for autoplay at the end of an episode.
public struct NextEpisode: Sendable {
    private let client: JellyfinClient
    private let userID: String

    /// Creates the finder.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    public init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    /// The episode after `episode` in its show, across seasons, or nil after the last one.
    ///
    /// The server answers with the episodes either side of the one asked about, so this is a single small
    /// request.
    public func after(_ episode: BaseItemDto) async throws -> BaseItemDto? {
        guard let episodeID = episode.id, let seriesID = episode.seriesID else { return nil }
        var parameters = Paths.GetEpisodesParameters(userID: userID)
        parameters.adjacentTo = episodeID
        parameters.fields = [.primaryImageAspectRatio, .overview]
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = [.primary, .backdrop, .thumb]
        let episodes: [BaseItemDto]
        do {
            episodes =
                try await client.send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).value.items
                ?? []
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        return Self.episode(after: episodeID, in: episodes)
    }

    /// The episode listed after `episodeID`, if any.
    static func episode(after episodeID: String, in episodes: [BaseItemDto]) -> BaseItemDto? {
        guard let index = episodes.firstIndex(where: { $0.id == episodeID }), index + 1 < episodes.count else {
            return nil
        }
        return episodes[index + 1]
    }
}
