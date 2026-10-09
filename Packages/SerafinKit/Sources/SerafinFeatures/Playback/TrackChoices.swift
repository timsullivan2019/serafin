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
    /// The device's generated subtitles, as their row shows them, or nil when it offers none.
    var generatedSubtitles: TrackChoice?
    /// The subtitles showing.
    var selectedSubtitles: SubtitlePick
    /// Subtitles picked that are still on their way, or nil.
    var pendingSubtitles: SubtitlePick?

    /// The tracks of the version `plan` plays, with the subtitles the player shows.
    ///
    /// - Parameters:
    ///   - plan: How the version plays.
    ///   - subtitles: The subtitles showing.
    ///   - pending: Subtitles picked that are still on their way, or nil.
    ///   - generated: The generated subtitles the device offers, or nil.
    ///   - locale: The language names are in.
    init(
        plan: PlaybackPlan,
        subtitles: SubtitleSelection,
        pending: SubtitleSelection? = nil,
        generated: GeneratedSubtitles? = nil,
        locale: Locale = .current
    ) {
        self.init(
            audioStreams: plan.streams(.audio),
            subtitleStreams: plan.streams(.subtitle),
            selectedAudio: plan.audioStreamIndex ?? plan.mediaSource.defaultAudioStreamIndex,
            subtitles: subtitles,
            pending: pending,
            generated: generated,
            mergesTextTracks: plan.method != .directPlay,
            locale: locale
        )
    }

    /// The tracks among `audioStreams` and `subtitleStreams`.
    ///
    /// - Parameter mergesTextTracks: Whether text subtitles come in the server's HLS stream, where AVPlayer merges
    ///   tracks it can't tell apart. Then identical rows for them show once, and the first stands for the others.
    init(
        audioStreams: [MediaStream],
        subtitleStreams: [MediaStream],
        selectedAudio: Int?,
        subtitles selection: SubtitleSelection,
        pending: SubtitleSelection? = nil,
        generated: GeneratedSubtitles? = nil,
        mergesTextTracks: Bool = false,
        locale: Locale = .current
    ) {
        audio = audioStreams.compactMap { Self.choice(for: $0, locale: locale) }
        var subtitles: [TrackChoice] = []
        var merged: [Int: Int] = [:]
        for stream in subtitleStreams {
            guard let choice = Self.choice(for: stream, locale: locale) else { continue }
            if mergesTextTracks, stream.deliveryMethod == .hls,
                let twin = subtitles.first(where: { $0.title == choice.title && $0.detail == choice.detail }),
                let twinStream = subtitleStreams.first(where: { $0.index == twin.id }),
                twinStream.deliveryMethod == .hls
            {
                merged[choice.id] = twin.id
                continue
            }
            subtitles.append(choice)
        }
        self.subtitles = subtitles
        generatedSubtitles = generated.map { Self.choice(for: $0, locale: locale) }
        self.selectedAudio = selectedAudio
        let row = { (pick: SubtitlePick) -> SubtitlePick in
            guard case .track(let index) = pick, let twin = merged[index] else { return pick }
            return .track(twin)
        }
        selectedSubtitles = row(Self.pick(selection))
        pendingSubtitles = pending.map { row(Self.pick($0)) }
    }

    /// The picker's form of the subtitles the player shows.
    static func pick(_ selection: SubtitleSelection) -> SubtitlePick {
        switch selection {
        case .off: .off
        case .stream(let index): .track(index)
        case .generated: .generated
        }
    }

    /// The subtitles the player shows for a pick in the picker.
    static func selection(_ pick: SubtitlePick) -> SubtitleSelection {
        switch pick {
        case .off: .off
        case .track(let index): .stream(index)
        case .generated: .generated
        }
    }

    /// The generated subtitles' row: "Generated", with their language and where they come from.
    static func choice(for generated: GeneratedSubtitles, locale: Locale) -> TrackChoice {
        let from = String(
            localized: "Created from the audio", bundle: .module,
            comment: "Detail of subtitles the device generates from a video's audio.")
        let language = SubtitleRules.language(generated.languageTag).flatMap {
            locale.localizedString(forLanguageCode: $0)
        }
        return TrackChoice(
            id: -1,
            title: String(
                localized: "Generated", bundle: .module,
                comment: "Choice in the player for subtitles the device generates from the audio."),
            detail: language.map { "\($0) · \(from)" } ?? from
        )
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
        // A track's own name often already says what it is, as in "English Forced" or "Surround 5.1".
        let alreadySaid = { (detail: String) in name?.localizedCaseInsensitiveContains(detail) == true }
        if stream.type == .subtitle {
            let forced = String(
                localized: "Forced", bundle: .module, comment: "Subtitles shown only for foreign speech.")
            if stream.isForced == true, !alreadySaid(forced) {
                details.append(forced)
            }
            let hearingImpaired = String(
                localized: "SDH", bundle: .module,
                comment: "Subtitles for the deaf and hard of hearing, as a short label.")
            if stream.isHearingImpaired == true, !alreadySaid(hearingImpaired) {
                details.append(hearingImpaired)
            }
        }
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
