import Foundation
import JellyfinAPI
import SerafinDesign
import SerafinPlayback

/// The audio and subtitle tracks of the version playing, as the track picker lists them.
struct TrackChoices: Equatable {
    /// The audio tracks.
    var audio: [TrackChoice]
    /// The server's number for the audio playing.
    var selectedAudio: Int?
    /// The subtitle tracks.
    var subtitles: [TrackChoice]
    /// The server's number for the subtitles showing, or nil when they are off.
    var selectedSubtitle: Int?

    /// The tracks of the version `plan` plays, with its current choices.
    init(plan: PlaybackPlan, locale: Locale = .current) {
        let audio = plan.audioStreamIndex ?? plan.mediaSource.defaultAudioStreamIndex
        let subtitle = plan.subtitleStreamIndex ?? plan.mediaSource.defaultSubtitleStreamIndex
        self.init(
            audioStreams: plan.streams(.audio),
            subtitleStreams: plan.streams(.subtitle),
            selectedAudio: audio,
            selectedSubtitle: subtitle,
            locale: locale
        )
    }

    /// The tracks among `audioStreams` and `subtitleStreams`.
    ///
    /// - Parameter selectedSubtitle: The subtitles showing, where -1 or nil means off.
    init(
        audioStreams: [MediaStream],
        subtitleStreams: [MediaStream],
        selectedAudio: Int?,
        selectedSubtitle: Int?,
        locale: Locale = .current
    ) {
        audio = audioStreams.compactMap { Self.choice(for: $0, locale: locale) }
        subtitles = subtitleStreams.compactMap { Self.choice(for: $0, locale: locale) }
        self.selectedAudio = selectedAudio
        self.selectedSubtitle = selectedSubtitle.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// A stream as the picker lists it: its language as the title, then its own name, format and channels.
    static func choice(for stream: MediaStream, locale: Locale) -> TrackChoice? {
        guard let index = stream.index else { return nil }
        let language = stream.language.flatMap { locale.localizedString(forLanguageCode: $0) }
        let name = stream.title.flatMap { $0.isEmpty ? nil : $0 }
        let title =
            language ?? name ?? stream.displayTitle
            ?? String(localized: "Track \(index)", bundle: .module, comment: "A track with no language or name.")
        var details: [String] = []
        if let name, name != title {
            details.append(name)
        }
        if stream.type == .subtitle {
            if stream.isForced == true {
                details.append(
                    String(localized: "Forced", bundle: .module, comment: "Subtitles shown only for foreign speech."))
            }
            if stream.isHearingImpaired == true {
                details.append(
                    String(
                        localized: "SDH", bundle: .module,
                        comment: "Subtitles for the deaf and hard of hearing, as a short label."))
            }
        }
        // A track's own name often already says its format or channels, as in "Surround 5.1".
        let alreadySaid = { (detail: String) in name?.localizedCaseInsensitiveContains(detail) == true }
        if let codec = stream.codec, !alreadySaid(Self.formatName(codec)) {
            details.append(Self.formatName(codec))
        }
        if stream.type == .audio, let layout = stream.channelLayout, !alreadySaid(Self.channelsName(layout)) {
            details.append(Self.channelsName(layout))
        }
        return TrackChoice(id: index, title: title, detail: details.isEmpty ? nil : details.joined(separator: " · "))
    }

    /// The name people know a codec by, such as "Dolby Digital Plus" for eac3.
    static func formatName(_ codec: String) -> String {
        let names = [
            "aac": "AAC", "ac3": "Dolby Digital", "eac3": "Dolby Digital Plus", "truehd": "Dolby TrueHD",
            "dts": "DTS", "flac": "FLAC", "alac": "ALAC", "mp3": "MP3", "opus": "Opus", "vorbis": "Vorbis",
            "subrip": "SRT", "srt": "SRT", "ass": "SSA", "ssa": "SSA", "pgssub": "PGS", "dvdsub": "VobSub",
            "dvbsub": "DVB", "mov_text": "Text", "webvtt": "WebVTT", "vtt": "WebVTT",
        ]
        return names[codec.lowercased()] ?? codec.uppercased()
    }

    /// A channel layout as people say it, such as "Stereo" or "5.1".
    static func channelsName(_ layout: String) -> String {
        let base = layout.split(separator: "(").first.map(String.init) ?? layout
        switch base.lowercased() {
        case "mono":
            return String(localized: "Mono", bundle: .module, comment: "One audio channel.")
        case "stereo":
            return String(localized: "Stereo", bundle: .module, comment: "Two audio channels.")
        default:
            return base
        }
    }
}
