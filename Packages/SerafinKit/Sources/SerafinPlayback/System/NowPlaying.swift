#if canImport(UIKit)
    import AVFoundation
    import MediaPlayer
    import UIKit

    /// Puts what's playing on the Lock Screen and in Control Center, and answers their buttons, AirPods presses and
    /// the scrubber.
    ///
    /// Command handlers can be called off the main thread, so each hops to the main actor.
    ///
    /// The session publishes elapsed time, duration and rate on its own; the title, subtitle and artwork come from
    /// the player item's Now Playing info.
    @MainActor final class NowPlaying {
        private let session: MPNowPlayingSession

        init(engine: PlayerEngine) {
            session = MPNowPlayingSession(players: [engine.player])
            session.automaticallyPublishesNowPlayingInfo = true
            let commands = session.remoteCommandCenter
            commands.playCommand.addTarget { @Sendable [weak engine] _ in
                Task { @MainActor in engine?.play() }
                return .success
            }
            commands.pauseCommand.addTarget { @Sendable [weak engine] _ in
                Task { @MainActor in engine?.pause() }
                return .success
            }
            commands.togglePlayPauseCommand.addTarget { @Sendable [weak engine] _ in
                Task { @MainActor in engine?.togglePlayPause() }
                return .success
            }
            commands.skipForwardCommand.preferredIntervals = [10]
            commands.skipForwardCommand.addTarget { @Sendable [weak engine] _ in
                Task { @MainActor in await engine?.skip(by: 10) }
                return .success
            }
            commands.skipBackwardCommand.preferredIntervals = [10]
            commands.skipBackwardCommand.addTarget { @Sendable [weak engine] _ in
                Task { @MainActor in await engine?.skip(by: -10) }
                return .success
            }
            commands.changePlaybackPositionCommand.addTarget { @Sendable [weak engine] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                let position = Duration.milliseconds(Int64(event.positionTime * 1000))
                Task { @MainActor in await engine?.seek(to: position) }
                return .success
            }
        }

        /// Makes this app the one the Lock Screen and Control Center show.
        func becomeActive() {
            session.becomeActiveIfPossible { _ in }
        }
    }

    /// What the Lock Screen shows for an item.
    struct NowPlayingDetails {
        let title: String
        let subtitle: String?
        let artwork: Data?

        /// The details as Now Playing info on a player item, which the session publishes alongside the playback
        /// state it tracks itself. The Lock Screen and Control Center read the title and artwork from here.
        var nowPlayingInfo: [String: Any] {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: title,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            ]
            if let subtitle {
                info[MPMediaItemPropertyArtist] = subtitle
            }
            if let artwork, let image = UIImage(data: artwork) {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
            return info
        }

        /// The details as metadata on a player item, which the Now Playing session reads.
        var metadata: [AVMetadataItem] {
            var items = [Self.item(.commonIdentifierTitle, title)]
            if let subtitle {
                items.append(Self.item(.iTunesMetadataTrackSubTitle, subtitle))
            }
            if let artwork {
                let item = AVMutableMetadataItem()
                item.identifier = .commonIdentifierArtwork
                item.value = artwork as NSData
                item.dataType = kCMMetadataBaseDataType_JPEG as String
                item.extendedLanguageTag = "und"
                items.append(item)
            }
            return items
        }

        private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }
    }
#endif
