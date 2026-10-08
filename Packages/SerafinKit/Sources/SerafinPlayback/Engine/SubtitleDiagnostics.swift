import AVFoundation
import Foundation
import JellyfinAPI
import MediaAccessibility
import SerafinCore
import os

/// Logs where subtitles on screen can come from, at playback start and on every change, for finding subtitles that
/// show twice or not at all. Debug builds only, under the "subtitles" category.
///
/// Each entry covers every layer that can draw subtitles: the server's plan (the stream asked for, and whether it's
/// burned into the picture), the `#EXT-X-MEDIA:TYPE=SUBTITLES` renditions in the server's HLS playlist, AVPlayer's
/// legible options and the one selected, whether AVPlayer applies media selection criteria by itself, and the system's
/// caption setting. Stream addresses carry the account's token, so none is ever logged.
enum SubtitleDiagnostics {
    static let logger = Logger(serafinCategory: "subtitles")

    /// Logs every subtitle layer of `player`'s current item, which plays `plan`, after `event`.
    ///
    /// - Parameters:
    ///   - event: What just happened, such as "loaded" or "picked off".
    ///   - plan: How the item is delivered.
    ///   - selection: The subtitles the engine means to show.
    ///   - player: The player.
    ///   - session: Fetches the server's playlist, with the account's certificate pins.
    @MainActor static func log(
        _ event: String, plan: PlaybackPlan?, selection: SubtitleSelection, player: AVPlayer, session: URLSession
    ) async {
        #if DEBUG
            guard let plan else {
                logger.debug("\(event, privacy: .public): nothing playing")
                return
            }
            logger.debug(
                "\(event, privacy: .public): showing \(String(describing: selection), privacy: .public), \(describe(plan), privacy: .public)"
            )
            if plan.method != .directPlay {
                let playlist = await masterPlaylist(at: plan.url, session: session)
                logger.debug("HLS subtitle renditions: \(playlist, privacy: .public)")
            }
            if let playerItem = player.currentItem {
                let burnedIn = PlayerEngine.isBurnedIn(plan.subtitleStreamIndex, in: plan.streams(.subtitle))
                let legible = await describeLegible(of: playerItem, burnedIn: burnedIn)
                logger.debug("AVPlayer legible: \(legible, privacy: .public)")
            }
            logger.debug("AVPlayer automatic selection: \(describeCriteria(of: player), privacy: .public)")
            logger.debug("System captions: \(describeSystemCaptions(), privacy: .public)")
        #endif
    }

    /// The plan's delivery, the subtitles it asked for, whether they're burned in, and every subtitle stream.
    static func describe(_ plan: PlaybackPlan) -> String {
        let subtitles = plan.streams(.subtitle)
        let selected = plan.subtitleStreamIndex.map(String.init) ?? "none"
        let burnedIn = PlayerEngine.isBurnedIn(plan.subtitleStreamIndex, in: subtitles)
        let serverDefault = plan.mediaSource.defaultSubtitleStreamIndex.map(String.init) ?? "none"
        let streams = subtitles.map(describe).joined(separator: "; ")
        return "method=\(plan.method) subtitle=\(selected) burnIn=\(burnedIn) serverDefault=\(serverDefault) "
            + "streams=[\(streams)]"
    }

    /// A subtitle stream as the log shows it: its index, format, language, flags and how the server delivers it.
    static func describe(_ stream: MediaStream) -> String {
        var parts = ["#\(stream.index.map(String.init) ?? "?")", stream.codec ?? "?", stream.language ?? "und"]
        if stream.isForced == true { parts.append("forced") }
        if stream.isHearingImpaired == true { parts.append("SDH") }
        if stream.isDefault == true { parts.append("default") }
        if stream.isExternal == true { parts.append("external") }
        parts.append(stream.deliveryMethod.map { "\($0.rawValue)" } ?? "delivery?")
        return parts.joined(separator: " ")
    }

    /// The subtitle and closed-caption renditions an HLS playlist declares, without their addresses, which carry the
    /// token.
    static func subtitleRenditions(inPlaylist playlist: String) -> [String] {
        playlist.split(whereSeparator: \.isNewline)
            .filter {
                $0.hasPrefix("#EXT-X-MEDIA:") && ($0.contains("TYPE=SUBTITLES") || $0.contains("TYPE=CLOSED-CAPTIONS"))
            }
            .map { line in
                String(line.dropFirst("#EXT-X-MEDIA:".count))
                    .replacing(/URI="[^"]*"/, with: "URI=…")
            }
    }

    /// What each variant of an HLS playlist says about closed captions in its video. Without a `CLOSED-CAPTIONS`
    /// attribute, AVPlayer assumes the video may carry them and offers them as a subtitle option.
    static func closedCaptions(inPlaylist playlist: String) -> [String] {
        playlist.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("#EXT-X-STREAM-INF:") }
            .map { line in
                guard let match = line.firstMatch(of: /CLOSED-CAPTIONS=("[^"]*"|[A-Z]+)/) else {
                    return "CLOSED-CAPTIONS absent"
                }
                return String(match.output.0)
            }
    }

    #if DEBUG
        private static func masterPlaylist(at url: URL, session: URLSession) async -> String {
            do {
                let (data, _) = try await session.data(from: url)
                let playlist = String(decoding: data, as: UTF8.self)
                let renditions = subtitleRenditions(inPlaylist: playlist)
                let captions = Set(closedCaptions(inPlaylist: playlist)).sorted()
                return (renditions.isEmpty ? "none" : renditions.joined(separator: " | "))
                    + "; variants: \(captions.joined(separator: ", "))"
            } catch {
                return "couldn't fetch the playlist"
            }
        }

        @MainActor private static func describeLegible(of playerItem: AVPlayerItem, burnedIn: Bool) async -> String {
            guard let group = try? await playerItem.asset.loadMediaSelectionGroup(for: .legible) else {
                return "no legible group"
            }
            let selected = playerItem.currentMediaSelection.selectedMediaOption(in: group)
            let selectable = PlayerEngine.selectableOptions(in: group, of: playerItem)
            let options = group.options.enumerated().map { position, option in
                var parts = [
                    "\(position):", option.mediaType.rawValue,
                    option.extendedLanguageTag ?? option.locale?.identifier ?? "und",
                ]
                if option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) { parts.append("forced") }
                if option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility) { parts.append("SDH") }
                if option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility) { parts.append("sounds") }
                if option.hasMediaCharacteristic(.machineGenerated) { parts.append("machine-generated") }
                if let selectable, !selectable.contains(option) { parts.append("unselectable") }
                if option == selected { parts.append("SELECTED") }
                return parts.joined(separator: " ")
            }
            let automatic = playerItem.currentMediaSelection.mediaSelectionCriteriaCanBeAppliedAutomatically(to: group)
            // Burned-in subtitles and a legible option at once are the double subtitles this log was made to find.
            let check =
                burnedIn
                ? (selected == nil ? " burn-in check: legible nil" : " burn-in check: CONFLICT, legible selected") : ""
            return "options=[\(options.joined(separator: "; "))] selected=\(selected == nil ? "nil" : "yes") "
                + "groupAllowsEmpty=\(group.allowsEmptySelection) criteriaCanApply=\(automatic)\(check)"
        }

        @MainActor private static func describeCriteria(of player: AVPlayer) -> String {
            let criteria = player.mediaSelectionCriteria(forMediaCharacteristic: .legible)
            let described =
                criteria.map {
                    "languages=\($0.preferredLanguages ?? []) characteristics="
                        + "\(($0.preferredMediaCharacteristics ?? []).map(\.rawValue))"
                } ?? "none"
            return "appliesMediaSelectionCriteriaAutomatically=\(player.appliesMediaSelectionCriteriaAutomatically) "
                + "legibleCriteria=\(described)"
        }

        private static func describeSystemCaptions() -> String {
            let displayType =
                switch MACaptionAppearanceGetDisplayType(.user) {
                case .forcedOnly: "forcedOnly"
                case .automatic: "automatic"
                case .alwaysOn: "alwaysOn"
                @unknown default: "unknown"
                }
            let characteristics =
                MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(.user).takeRetainedValue() as? [String]
                ?? []
            let languages = MACaptionAppearanceCopySelectedLanguages(.user).takeRetainedValue() as? [String] ?? []
            return "displayType=\(displayType) preferredCharacteristics=\(characteristics) languages=\(languages)"
        }
    #endif
}
