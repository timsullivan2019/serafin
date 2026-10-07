import Observation
import SerafinDesign
import SwiftUI

/// Marks items played and favourite from any screen, then has every screen showing them reload.
@Observable @MainActor final class MediaActions {
    /// A change a person made that the server accepted, for the haptic that confirms it.
    struct Confirmation: Equatable {
        /// What changed.
        enum Kind: Equatable {
            case played, unplayed, favourite, notFavourite, refreshing
        }

        let kind: Kind
        /// Tells two confirmations of the same kind apart.
        let number: Int

        /// Success for marking played, as the design rules ask, and a light tick for the rest.
        var feedback: SensoryFeedback {
            kind == .played ? .success : .selection
        }

        /// What VoiceOver says once the change goes through, since the button only changes its label.
        var announcement: String {
            switch kind {
            case .played:
                String(
                    localized: "Marked as watched", bundle: .module, comment: "Spoken once an item is marked watched.")
            case .unplayed:
                String(
                    localized: "Marked as unwatched", bundle: .module,
                    comment: "Spoken once an item is marked unwatched."
                )
            case .favourite:
                String(localized: "Added to Favourites", bundle: .module, comment: "Spoken once a favourite is added.")
            case .notFavourite:
                String(
                    localized: "Removed from Favourites", bundle: .module,
                    comment: "Spoken once a favourite is taken out.")
            case .refreshing:
                String(
                    localized: "Refreshing metadata", bundle: .module,
                    comment: "Spoken once the server has been asked to refresh an item's metadata.")
            }
        }
    }

    /// Goes up by one after every change, so screens showing played marks and favourites reload.
    private(set) var revision = 0
    /// The last change a person made that went through. Playback marking an item played doesn't count.
    private(set) var confirmation: Confirmation?
    /// The last change that failed, shown as an alert.
    var failure: UserMessage?

    /// Marks `item` played or not.
    func setPlayed(_ isPlayed: Bool, for item: MediaItem, in media: any MediaSource) async {
        await change(isPlayed ? .played : .unplayed) { try await media.setPlayed(isPlayed, for: item) }
    }

    /// Asks the server to refresh `item`'s metadata. The server does it in the background, so screens reload now and
    /// show the new details the next time they load.
    func refreshMetadata(of item: MediaItem, in media: any MediaSource) async {
        await change(.refreshing) { try await media.refreshMetadata(of: item) }
    }

    /// Has every screen reload, as after playback changes an item's progress.
    func reload() {
        revision += 1
    }

    /// Adds `item` to the favourites or takes it out.
    func setFavourite(_ isFavourite: Bool, for item: MediaItem, in media: any MediaSource) async {
        await change(isFavourite ? .favourite : .notFavourite) { try await media.setFavourite(isFavourite, for: item) }
    }

    private func change(_ kind: Confirmation.Kind, _ send: () async throws -> Void) async {
        do {
            try await send()
            revision += 1
            confirmation = Confirmation(kind: kind, number: revision)
        } catch is CancellationError {
        } catch {
            failure = UserMessage(error)
        }
    }
}

/// The items in a card's context menu: Play, Go to Show for an episode, Mark as Watched and Favourite.
struct CardMenuItems: View {
    let item: MediaItem
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(MediaActions.self) private var actions
    @Environment(\.media) private var media
    @Environment(\.navigate) private var navigate

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
        if let show = item.showRoute {
            Button {
                navigate(show)
            } label: {
                Label(
                    String(
                        localized: "Go to Show", bundle: .module,
                        comment: "Menu item on an episode that opens the show it belongs to."),
                    systemImage: "tv"
                )
            }
        }
        Button {
            Task { await actions.setPlayed(!item.card.isWatched, for: item, in: media) }
        } label: {
            if item.card.isWatched {
                Label(
                    String(
                        localized: "Mark as Unwatched", bundle: .module,
                        comment: "Button and menu item that marks an item not watched."),
                    systemImage: "circle.dashed"
                )
            } else {
                Label(
                    String(
                        localized: "Mark as Watched", bundle: .module,
                        comment: "Button and menu item that marks an item watched."),
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
