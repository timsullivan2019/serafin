import Observation
import SerafinDesign
import SwiftUI

/// Marks items played and favourite from any screen, then has every screen showing them reload.
@Observable @MainActor final class MediaActions {
    /// Goes up by one after every change, so screens showing played marks and favourites reload.
    private(set) var revision = 0
    /// The last change that failed, shown as an alert.
    var failure: UserMessage?

    /// Marks `item` played or not.
    func setPlayed(_ isPlayed: Bool, for item: MediaItem, in media: any MediaSource) async {
        await change { try await media.setPlayed(isPlayed, for: item) }
    }

    /// Adds `item` to the favourites or takes it out.
    func setFavourite(_ isFavourite: Bool, for item: MediaItem, in media: any MediaSource) async {
        await change { try await media.setFavourite(isFavourite, for: item) }
    }

    private func change(_ send: () async throws -> Void) async {
        do {
            try await send()
            revision += 1
        } catch is CancellationError {
        } catch {
            failure = UserMessage(error)
        }
    }
}

/// The items in a card's context menu: Play, Mark as Played and Favourite.
struct CardMenuItems: View {
    let item: MediaItem
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(MediaActions.self) private var actions
    @Environment(\.media) private var media

    var body: some View {
        // A show or season plays from its page, which knows the episode to start.
        if item.card.kind == .movie || item.card.kind == .episode {
            Button {
                playback.play(item)
            } label: {
                Label(
                    String(localized: "Play", bundle: .module, comment: "Menu item that starts playback."),
                    systemImage: "play.fill"
                )
            }
        }
        Button {
            Task { await actions.setPlayed(!item.card.isPlayed, for: item, in: media) }
        } label: {
            if item.card.isPlayed {
                Label(
                    String(
                        localized: "Mark as Unplayed", bundle: .module,
                        comment: "Button and menu item that marks an item not played."),
                    systemImage: "circle.dashed"
                )
            } else {
                Label(
                    String(
                        localized: "Mark as Played", bundle: .module,
                        comment: "Button and menu item that marks an item played."),
                    systemImage: "checkmark.circle"
                )
            }
        }
        Button {
            Task { await actions.setFavourite(!item.card.isFavourite, for: item, in: media) }
        } label: {
            if item.card.isFavourite {
                Label(
                    String(
                        localized: "Remove from Favourites", bundle: .module,
                        comment: "Button and menu item that takes an item out of the favourites."),
                    systemImage: "heart.slash"
                )
            } else {
                Label(
                    String(
                        localized: "Add to Favourites", bundle: .module,
                        comment: "Button and menu item that adds an item to the favourites."),
                    systemImage: "heart"
                )
            }
        }
    }
}
