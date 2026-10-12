import Nuke
import Observation
import SerafinCore
import SerafinDesign
import SwiftUI

/// What a movie, show or episode detail screen shows.
///
/// A show's page lists one season's episodes at a time. It opens on the season of the episode Play starts, with the
/// show's own artwork in the hero. Once the user picks another season, the hero follows it: the season's own picture,
/// and Play starting the season's first episode not yet watched. Picking the season the page opened on puts the hero
/// back as it opened, so a season looks the same every time it's picked. The episodes show as soon as they load; the
/// hero waits until the season's episodes and picture are both ready, then changes in one movement.
@Observable @MainActor final class ItemDetailModel {
    enum Phase {
        case loading
        case loaded(ItemDetails)
        case failed(UserMessage)
    }

    /// A picked season's own picture in the hero, with the tint taken from it.
    struct SeasonArtwork {
        let seasonID: String
        let image: Image
        let tint: Color
        /// Whether it's the season's poster, which the hero crops from the top, rather than a backdrop.
        let isPoster: Bool
    }

    /// The hero's size, and what decides which of a season's pictures it shows, for loading them at the size drawn.
    struct HeroGeometry: Equatable {
        var size: CGSize
        var scale: CGFloat
        /// Whether the screen is compact width, where a season's poster fills the hero when it has no backdrop.
        var isCompact: Bool
    }

    let id: String
    /// The item as the card that opened the screen showed it, for the navigation bar until the details load.
    let preview: MediaItem?
    private(set) var phase = Phase.loading
    /// Whether the user can ask the server to refresh the item's metadata, which administrators can.
    private(set) var canRefreshMetadata = false
    /// The tint taken from the item's own backdrop, or nil until it loads. An item whose backdrop was measured
    /// moments ago, as in Home's hero, starts with its tint.
    private var ownTint: Color?

    /// The season whose episodes the page lists.
    private(set) var selectedSeasonID: String?
    /// The episodes loaded so far, by season.
    private(set) var episodes: [String: [MediaItem]] = [:]
    /// The seasons whose episodes didn't load, which the page offers to try again.
    private(set) var failedSeasons: Set<String> = []
    /// The season the hero follows once the user has picked one, or nil while it shows the show itself.
    private(set) var heroSeasonID: String?
    /// The followed season's own picture, or nil when the hero keeps the show's.
    private(set) var seasonArtwork: SeasonArtwork?
    /// The season asked for by a link, which the page opens on instead of the season of the next episode.
    private let requestedSeasonID: String?
    /// The season the page opened on, which the hero shows with the show's own art.
    private var openedSeasonID: String?
    /// The episode a show's page was opened for, as from Home's hero, which Play starts until it's watched.
    private var pinnedEpisodeID: String?
    private var seasonChange: Task<Void, Never>?
    private var prefetcher: ImagePrefetcher?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - id: The movie, show or episode.
    ///   - seasonID: For a show, the season to list first, as from a link to the season.
    ///   - preview: The item as the card that opened the screen showed it.
    init(id: String, seasonID: String? = nil, preview: MediaItem? = nil) {
        self.id = id
        self.preview = preview
        requestedSeasonID = seasonID
        ownTint = ArtworkMemory.tint(for: id)
    }

    /// Starts with `item` showing, and for a show the episode its Play button starts, while the full details load. A
    /// show opened for an episode opens on the episode's season, and Play keeps starting that episode until it's
    /// watched, as what was tapped said it would.
    init(showing item: MediaItem, playable: MediaItem?) {
        id = item.id
        preview = item
        let episode = item.card.kind == .series ? playable.flatMap { $0.card.kind == .episode ? $0 : nil } : nil
        requestedSeasonID = episode?.seasonID
        pinnedEpisodeID = episode?.id
        phase = .loaded(ItemDetails(item: item, playable: playable ?? item))
        ownTint = item.source == nil ? MockMedia.tint(for: item.card) : ArtworkMemory.tint(for: item.id)
    }

    /// The details once they have loaded.
    var details: ItemDetails? {
        if case .loaded(let details) = phase { details } else { nil }
    }

    /// The screen's accent: the followed season's picture's, otherwise the item's backdrop's, or nil until that loads.
    var tint: Color? {
        seasonArtwork?.tint ?? ownTint
    }

    /// What the hero's Play starts: for a show, the episode Next Up names, or the one the page was opened for, until the
    /// user picks another season, then that season's first episode not yet watched; otherwise the item itself.
    var playable: MediaItem? {
        guard let details else { return nil }
        guard let heroSeasonID, let season = episodes[heroSeasonID], let first = Self.firstToWatch(in: season) else {
            return details.playable ?? details.item
        }
        return first
    }

    /// The media badges under the hero: those of the episode Play starts, for a show.
    var badges: [String] {
        guard heroSeasonID != nil, let playable else { return details?.badges ?? [] }
        return Self.badges(of: playable)
    }

    /// Loads the details, and whether the user may refresh their metadata. A failed reload keeps the details
    /// already showing.
    ///
    /// A show's page keeps the season it lists across reloads, as after marking an episode watched, and loads that
    /// season's episodes again with the details, so the page changes all at once.
    func load(from media: any MediaSource) async {
        async let canRefresh = media.canRefreshMetadata()
        do {
            var details = try await media.details(of: id)
            if details.item.source == nil {
                ownTint = MockMedia.tint(for: details.item.card)
            }
            let seasonIDs = Set(details.seasons.map(\.id))
            let listed =
                [selectedSeasonID, requestedSeasonID, details.openingSeasonID].lazy.compactMap { $0 }
                .first { seasonIDs.contains($0) }
            var loaded: [String: [MediaItem]] = [:]
            if let opening = details.openingSeasonID {
                loaded[opening] = details.openingEpisodes
            }
            // Other seasons' episodes are now out of date. The ones showing load again; the rest load when picked.
            for seasonID in Set([listed, heroSeasonID].compactMap { $0 }) where loaded[seasonID] == nil {
                loaded[seasonID] = try? await media.episodes(inSeason: seasonID, of: id)
            }
            // A season picked while this loaded stays picked, and a season showing keeps the episodes it had when
            // loading them again failed.
            let selected = selectedSeasonID.flatMap { seasonIDs.contains($0) ? $0 : nil } ?? listed
            for seasonID in [selected, heroSeasonID].compactMap({ $0 }) where loaded[seasonID] == nil {
                loaded[seasonID] = episodes[seasonID]
            }
            if let pinnedEpisodeID, let pinned = loaded.values.joined().first(where: { $0.id == pinnedEpisodeID }) {
                if pinned.card.isWatched {
                    // Watched since, so Play moves on with the show, as on any show's page.
                    self.pinnedEpisodeID = nil
                } else {
                    details.playable = pinned
                    details.badges = Self.badges(of: pinned)
                }
            }
            episodes = loaded
            failedSeasons = Set([selected].compactMap { $0 }.filter { loaded[$0] == nil })
            selectedSeasonID = selected
            if openedSeasonID == nil {
                openedSeasonID = selected
            }
            if let heroSeasonID, !seasonIDs.contains(heroSeasonID) {
                self.heroSeasonID = nil
                seasonArtwork = nil
            }
            phase = .loaded(details)
        } catch is CancellationError {
        } catch {
            if case .loaded = phase {} else { phase = .failed(UserMessage(error)) }
        }
        canRefreshMetadata = await canRefresh
    }

    /// Takes the tint from the loaded backdrop, fading to it from the neutral tint the screen starts with when it
    /// didn't know the colour yet.
    func backdropLoaded(_ image: CGImage) {
        let measured = ArtworkTint.color(for: image)
        ArtworkMemory.remember(measured, for: id)
        guard measured != ownTint else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            ownTint = measured
        }
    }

    // MARK: - Seasons

    /// Lists `seasonID`'s episodes, loading them first if need be, and has the hero follow the season once both its
    /// episodes and its picture are ready, so the artwork, its tint, Play and the badges change together.
    ///
    /// - Parameters:
    ///   - seasonID: The season picked.
    ///   - media: Where the episodes come from.
    ///   - artwork: Loads the season's picture from the server; nil for the samples.
    ///   - hero: The hero's size, for the picture's.
    /// - Returns: The work that has the hero follow, for tests to wait on, or nil when the season is already listed.
    @discardableResult
    func selectSeason(
        _ seasonID: String, from media: any MediaSource, artwork: Artwork?, hero: HeroGeometry
    ) -> Task<Void, Never>? {
        guard seasonID != selectedSeasonID, details?.seasons.contains(where: { $0.id == seasonID }) == true else {
            return nil
        }
        selectedSeasonID = seasonID
        return followSelectedSeason(from: media, artwork: artwork, hero: hero)
    }

    /// Loads the listed season's episodes and picture, then has the hero follow the season, as picking it does. Also
    /// what Try Again does once a season's episodes failed to load; until they load, the hero stays as it was.
    ///
    /// For the season the page opened on, the hero goes back to how the page opened: the show's own art, and Play
    /// starting the show's next episode.
    ///
    /// - Returns: The work that has the hero follow, for tests to wait on.
    @discardableResult
    func followSelectedSeason(
        from media: any MediaSource, artwork: Artwork?, hero: HeroGeometry
    ) -> Task<Void, Never>? {
        guard let seasonID = selectedSeasonID, let season = details?.seasons.first(where: { $0.id == seasonID }) else {
            return nil
        }
        seasonChange?.cancel()
        if seasonID == openedSeasonID {
            let change = Task {
                await loadEpisodes(of: seasonID, from: media)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    heroSeasonID = nil
                    seasonArtwork = nil
                }
            }
            seasonChange = change
            return change
        }
        let change = Task {
            async let listed: Void = loadEpisodes(of: seasonID, from: media)
            let picture = await Self.picture(of: season, artwork: artwork, hero: hero)
            await listed
            guard !Task.isCancelled, episodes[seasonID] != nil else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                heroSeasonID = seasonID
                seasonArtwork = picture
            }
        }
        seasonChange = change
        return change
    }

    /// Loads a season's episodes, unless they're loaded already.
    func loadEpisodes(of seasonID: String, from media: any MediaSource) async {
        guard episodes[seasonID] == nil else { return }
        do {
            let loaded = try await media.episodes(inSeason: seasonID, of: id)
            episodes[seasonID] = loaded
            failedSeasons.remove(seasonID)
        } catch is CancellationError {
        } catch {
            failedSeasons.insert(seasonID)
        }
    }

    /// Shows the picture the followed season has at a new hero size, as when an iPad window changes between compact
    /// and regular width: a poster only fills a compact hero.
    ///
    /// - Returns: The work that changes the picture, for tests to wait on, or nil when it stays.
    @discardableResult
    func heroChanged(to hero: HeroGeometry, artwork: Artwork?) -> Task<Void, Never>? {
        guard let heroSeasonID, let season = details?.seasons.first(where: { $0.id == heroSeasonID }) else {
            return nil
        }
        let showing: ImageRole? = seasonArtwork.map { $0.isPoster ? .poster : .backdrop }
        guard season.heroRole(isCompact: hero.isCompact) != showing else { return nil }
        seasonChange?.cancel()
        let change = Task {
            let picture = await Self.picture(of: season, artwork: artwork, hero: hero)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                seasonArtwork = picture
            }
        }
        seasonChange = change
        return change
    }

    /// Starts downloading every season's hero picture at the hero's size, so a season picked later shows its picture
    /// without waiting on the network. The pictures are kept on disk, not decoded, until a season is picked.
    func prefetchSeasonArtwork(artwork: Artwork?, hero: HeroGeometry) {
        guard let artwork, let seasons = details?.seasons, hero.size.width > 0, hero.size.height > 0 else { return }
        let requests = seasons.compactMap { Self.request(for: $0, artwork: artwork, hero: hero) }
        guard !requests.isEmpty else { return }
        if prefetcher == nil {
            prefetcher = ImagePrefetcher(pipeline: artwork.pipeline, destination: .diskCache)
        }
        prefetcher?.startPrefetching(with: requests)
    }

    /// Which episode a season's row starts at: the one Play starts, when it's in the season, otherwise the season's
    /// first episode not yet watched.
    func startingEpisode(in seasonID: String) -> String? {
        guard let season = episodes[seasonID] else { return nil }
        if let playable, season.contains(where: { $0.id == playable.id }) {
            return playable.id
        }
        return Self.firstToWatch(in: season)?.id
    }

    // MARK: - Helpers

    /// The episode Play starts in a season: the first not yet watched, counting one part way through, or the first
    /// when all of them are watched.
    nonisolated static func firstToWatch(in episodes: [MediaItem]) -> MediaItem? {
        episodes.first { !$0.card.isWatched } ?? episodes.first
    }

    /// An episode's media badges: from its streams, or a sample's made-up file.
    nonisolated static func badges(of episode: MediaItem) -> [String] {
        guard let source = episode.source else { return SampleMediaSource.badges(of: episode.card) }
        return MediaBadges.badges(for: source)
    }

    /// The width, in points, to ask for a season's picture at so it fills the hero: a backdrop as wide as Home's
    /// hero asks, a poster as wide as the hero, or wider when the hero is very tall.
    static func pictureWidth(_ role: ImageRole, of seasonID: String, hero: HeroGeometry) -> CGFloat {
        guard role == .poster else { return ArtworkMemory.backdropWidth(for: seasonID, filling: hero.size) }
        return max(hero.size.width, hero.size.height * 2 / 3)
    }

    /// The request for the picture `season` shows in the hero, or nil when it keeps the show's.
    private static func request(for season: ShowSeason, artwork: Artwork, hero: HeroGeometry) -> ImageRequest? {
        guard let role = season.heroRole(isCompact: hero.isCompact), let source = season.item.source else {
            return nil
        }
        let width = pictureWidth(role, of: season.id, hero: hero)
        guard width > 0 else { return nil }
        return artwork.request(role, of: source, width: width, scale: hero.scale)
    }

    /// Loads the picture `season` shows in the hero and measures its tint, or nil when it has none to show, in which
    /// case the hero keeps the show's art. The samples draw generated art.
    private static func picture(of season: ShowSeason, artwork: Artwork?, hero: HeroGeometry) async -> SeasonArtwork? {
        guard let role = season.heroRole(isCompact: hero.isCompact) else { return nil }
        let image: CGImage?
        if let artwork, season.item.source != nil {
            guard let request = request(for: season, artwork: artwork, hero: hero),
                let loaded = try? await artwork.pipeline.image(for: request)
            else { return nil }
            image = loaded.bitmap
        } else {
            image =
                role == .poster ? MockMedia.poster(for: season.item.card) : MockMedia.backdrop(for: season.item.card)
        }
        guard let image else { return nil }
        let tint = ArtworkTint.color(for: image)
        ArtworkMemory.remember(tint, for: season.id)
        return SeasonArtwork(
            seasonID: season.id, image: Image(decorative: image, scale: 1), tint: tint, isPoster: role == .poster)
    }
}
