import Foundation
import JellyfinAPI
import SerafinDesign

/// A movie's or an episode's versions, such as its 4K file and its 1080p one, as the detail screen's version list, the
/// player's Version section and the download menu show them: each with its name, its badges and its size.
enum MediaVersions {
    /// The most versions a list shows, well beyond any real library's, so a server that lists a great many can't
    /// flood the screen.
    static let maximumListed = 24

    /// `versions` as the lists show them, in the server's order, at most ``maximumListed``. A version without an ID
    /// can't be asked for, so it's left out.
    static func choices(for versions: [MediaSourceInfo]) -> [VersionChoice] {
        var choices: [VersionChoice] = []
        for (offset, version) in versions.enumerated() {
            guard choices.count < maximumListed else { break }
            guard let id = version.id, !id.isEmpty else { continue }
            choices.append(
                VersionChoice(
                    id: id,
                    title: title(of: version, number: offset + 1),
                    badges: MediaBadges.badges(for: version),
                    size: size(of: version)
                ))
        }
        return choices
    }

    /// A version's name: the server's, such as "4K Remux", which it takes from the file's name, or else its format,
    /// such as "4K · HEVC · Dolby Vision · Atmos", or else "Version 2", for the `number`th version.
    static func title(of version: MediaSourceInfo, number: Int) -> String {
        if let name = version.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return format(of: version)
            ?? String(
                localized: "Version \(number)", bundle: .module,
                comment: "A video's version that has no name and no known format, such as Version 2.")
    }

    /// A version's format from its streams: its resolution, video codec, dynamic range and audio, such as
    /// "4K · HEVC · Dolby Vision · Atmos" or "1080p · H.264 · AAC", or nil when the server lists none of them.
    static func format(of version: MediaSourceInfo) -> String? {
        let streams = version.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio =
            streams.first { $0.type == .audio && $0.index == version.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }
        let parts = [
            video.flatMap(ItemInformation.resolution(of:)),
            video?.codec.flatMap(videoCodecName),
            video?.videoRangeType.flatMap(ItemInformation.rangeName),
            audio.flatMap(audioName),
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How big a version's file is, such as "4.2 GB", or nil when the server doesn't say.
    static func size(of version: MediaSourceInfo) -> String? {
        guard let bytes = version.size, bytes > 0 else { return nil }
        return DownloadRow.size(Int64(bytes))
    }

    /// The name people know a video codec by, such as "H.264" for h264, or nil when the server names none.
    static func videoCodecName(_ codec: String) -> String? {
        let names = [
            "h264": "H.264", "avc": "H.264", "hevc": "HEVC", "h265": "HEVC", "av1": "AV1", "vp9": "VP9", "vp8": "VP8",
            "mpeg2video": "MPEG-2", "mpeg4": "MPEG-4", "vc1": "VC-1",
        ]
        let codec = codec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codec.isEmpty else { return nil }
        return names[codec.lowercased()] ?? codec.uppercased()
    }

    /// The audio's name in a version's format: Atmos when the server names it in the track, as for TrueHD and E-AC-3
    /// with Atmos, otherwise its format, such as "Dolby Digital Plus", or nil when the server names none.
    static func audioName(_ audio: MediaStream) -> String? {
        if MediaBadges.audioBadges(of: audio).contains("Dolby Atmos") {
            return "Atmos"
        }
        guard let codec = audio.codec, !codec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return TrackChoices.formatName(codec)
    }

    // MARK: - Where they were left

    /// The most versions of one item whose user data the detail screen asks for, so a server that lists a great many
    /// can't have it send a request for each.
    static let maximumAsked = 8

    /// Where `versions` were left part way through: the version with a position that was played most recently, as
    /// Jellyfin's own Continue Watching picks, or nil when none has a position.
    ///
    /// Jellyfin 12.0 and later keep each version's position on that version, and give the item that lists the versions
    /// the date of the one played most recently, so the two share a date. The server lists that version first on the
    /// item's page, and a version's own page lists itself first, so on a tie the version listed first wins. Jellyfin
    /// 10.11 keeps one position, on the item played, so its dates don't tie.
    ///
    /// - Parameters:
    ///   - itemID: The movie or episode whose versions they are.
    ///   - versions: The versions, in the server's order.
    ///   - records: The user's data for the versions, by version ID.
    static func resumePoint(
        of itemID: String, among versions: [MediaSourceInfo], records: [String: UserItemDataDto]
    ) -> ResumePoint? {
        var latest: ResumePoint?
        var latestDate = Date.distantPast
        for version in versions {
            guard let id = version.id, let record = records[id], (record.playbackPositionTicks ?? 0) > 0 else {
                continue
            }
            let date = record.lastPlayedDate ?? .distantPast
            if latest == nil || date > latestDate {
                latest = ResumePoint(itemID: itemID, versionID: id, userData: record)
                latestDate = date
            }
        }
        return latest
    }
}

/// Where a movie or an episode with more than one version was left part way through: the version, and the user's data
/// for it, with the position Play resumes from.
struct ResumePoint: Equatable, Sendable {
    /// The movie or episode.
    let itemID: String
    /// Its version that was left part way through.
    let versionID: String
    /// The user's data for that version, as the server has it.
    let userData: UserItemDataDto

    /// Whether it's in another version than the item's own file, whose position the item's own data doesn't have on
    /// Jellyfin 12.0 and later.
    var isInAnotherVersion: Bool {
        versionID != itemID
    }
}

extension MediaItem {
    /// The item with the position, progress and last-played date of `userData`, another version's, so its card shows
    /// that progress and Play resumes from that position. Nil for an item without the server's details, as a sample.
    func resumed(at userData: UserItemDataDto) -> MediaItem? {
        guard var item = source else { return nil }
        var own = item.userData ?? UserItemDataDto(key: userData.key)
        own.playbackPositionTicks = userData.playbackPositionTicks
        own.playedPercentage = userData.playedPercentage
        own.lastPlayedDate = userData.lastPlayedDate
        item.userData = own
        return MediaItem(item)
    }
}
