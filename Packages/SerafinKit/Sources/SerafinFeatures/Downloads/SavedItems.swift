import CoreGraphics
import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import SerafinPlayback
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// The pictures saved on the device with a download, which its cards and detail screen draw with no server.
struct SavedArtwork: Hashable, Sendable {
    /// The 2:3 poster, or nil when none was saved.
    var poster: URL?
    /// The full-bleed backdrop, or nil when none was saved.
    var backdrop: URL?

    /// The picture that suits `role`: the poster for a poster, and the backdrop for every 16:9 picture. A logo has
    /// none, and the title shows in its place.
    func url(for role: ImageRole) -> URL? {
        switch role {
        case .poster: poster
        case .landscape, .backdrop, .watching: backdrop
        case .logo: nil
        }
    }
}

extension DownloadArtwork {
    /// The role whose picture is saved as this one.
    var role: ImageRole {
        switch self {
        case .poster: .poster
        case .backdrop: .backdrop
        }
    }
}

extension MediaItem {
    /// A downloaded movie or episode as what was saved with it describes it, for showing and playing it with no
    /// server: its details and pictures, and how far it's been watched as the device last knew.
    ///
    /// The player and the screens take an item from the server, so the item carries one made from what was saved: its
    /// ID, title, kind, running time and place in its show, and nothing that needs the server, such as picture tags.
    init(download record: DownloadRecord, artwork: SavedArtwork) {
        let metadata = record.metadata
        let kind: BaseItemKind = metadata.kind == .episode ? .episode : .movie
        let runtime = metadata.runtime
        let resume = record.playback?.resumePosition(runtime: runtime) ?? .zero
        var progress = 0.0
        if let runtime, runtime > .zero, resume > .zero {
            progress = resume / runtime
        }
        var episode: MediaCard.EpisodeInfo?
        if kind == .episode {
            episode = MediaCard.EpisodeInfo(
                seriesID: metadata.seriesID ?? "",
                seriesTitle: metadata.seriesName ?? "",
                seasonNumber: metadata.seasonNumber ?? 0,
                episodeNumber: metadata.episodeNumber ?? 0
            )
        }
        let card = MediaCard(
            id: record.itemID,
            kind: kind == .episode ? .episode : .movie,
            title: metadata.title,
            year: metadata.year,
            runtime: runtime,
            rating: metadata.rating,
            progress: progress,
            isPlayed: record.playback?.isPlayed(runtime: runtime) ?? false,
            overview: metadata.overview,
            episode: episode
        )
        var source = BaseItemDto(id: record.itemID, name: metadata.title, type: kind)
        source.runTimeTicks = runtime.map(Ticks.from)
        source.productionYear = metadata.year
        if kind == .episode {
            source.seriesID = metadata.seriesID
            source.seriesName = metadata.seriesName
            source.parentIndexNumber = metadata.seasonNumber
            source.indexNumber = metadata.episodeNumber
        }
        self.init(card: card, source: source, savedArtwork: artwork)
    }

    /// Whether this episode and `other` are in the same season of the same show, by the show's ID, or its name for
    /// episodes that weren't saved with the ID.
    fileprivate func isInSameSeason(as other: MediaItem) -> Bool {
        guard let mine = card.episode, let theirs = other.card.episode, mine.seasonNumber == theirs.seasonNumber else {
            return false
        }
        if !mine.seriesID.isEmpty, !theirs.seriesID.isEmpty {
            return mine.seriesID == theirs.seriesID
        }
        return !mine.seriesTitle.isEmpty && mine.seriesTitle == theirs.seriesTitle
    }
}

extension ItemDetails {
    /// What a detail screen shows for the downloaded item `itemID` from what was saved with it, among the account's
    /// downloads as `items`: the item, which Play starts from its file, and for an episode the other episodes of its
    /// season that are downloaded too, in order. Nil when the item isn't among them.
    static func saved(_ itemID: String, among items: [MediaItem]) -> ItemDetails? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        var details = ItemDetails(item: item, playable: item)
        if item.card.kind == .episode {
            details.seasonEpisodes =
                items
                .filter { $0.id != itemID && $0.isInSameSeason(as: item) }
                .sorted { ($0.card.episode?.episodeNumber ?? 0) < ($1.card.episode?.episodeNumber ?? 0) }
        }
        return details
    }
}

/// How wide a download's poster and backdrop are saved: as wide as the screen Serafin shows on draws them, so they
/// look as sharp as they do streaming, and no wider.
struct DownloadArtworkSizes: Equatable {
    /// The widest a poster card gets, in points: a column of a grid of posters at the largest text sizes, as on an iPad
    /// held upright, whose screen fits two.
    static let posterLimit: CGFloat = 500
    /// The narrowest width iOS gives a regular-width window that fills the screen, as on the smallest iPad held
    /// upright. Every iPhone held upright is narrower.
    static let regularWidth: CGFloat = 700

    /// The poster's width, in points: the widest a poster card gets on the screen.
    let poster: CGFloat
    /// The backdrop's width, in points: the widest the detail screen's hero asks for on the screen, upright or
    /// sideways, at any text size.
    let backdrop: CGFloat
    /// The screen's scale, which turns points into pixels.
    let scale: CGFloat

    /// The sizes for a screen `screen` points in size, at `scale`.
    init(screen: CGSize, scale: CGFloat) {
        let short = min(screen.width, screen.height)
        let long = max(screen.width, screen.height)
        poster = min(max(short - Spacing.medium * 2, 0), Self.posterLimit)
        backdrop = max(
            Self.heroBackdrop(width: short, screenHeight: long),
            Self.heroBackdrop(width: long, screenHeight: short)
        )
        self.scale = scale
    }

    /// The width, in points, a picture of `kind` is saved at.
    func width(of kind: DownloadArtwork) -> CGFloat {
        switch kind {
        case .poster: poster
        case .backdrop: backdrop
        }
    }

    /// The backdrop width the detail screen's hero asks for on a screen `width` points wide and `screenHeight` tall,
    /// at the largest text sizes, where the hero is tallest.
    private static func heroBackdrop(width: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let fraction = HomeHeroLayout.heightFraction(
            isRegularWidth: width >= regularWidth, dynamicTypeSize: .accessibility5)
        return HomeHeroPage.backdropWidth(for: CGSize(width: width, height: screenHeight * fraction))
    }

    /// The sizes for the screen Serafin shows on.
    @MainActor static var current: DownloadArtworkSizes {
        #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen {
                return DownloadArtworkSizes(screen: screen.bounds.size, scale: screen.scale)
            }
        #endif
        // With no screen to measure, as in tests on a Mac, a large iPad's.
        return DownloadArtworkSizes(screen: CGSize(width: 1032, height: 1376), scale: 2)
    }
}
