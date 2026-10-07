import JellyfinAPI

extension DeviceProfile {
    /// The bitrate Serafin asks for when the user sets no cap: 120 Mbps, above any Blu-ray remux.
    public static let uncappedBitrate = 120_000_000

    /// What Serafin's AVPlayer can play as it is, and what the server should make when it can't.
    ///
    /// - Direct play: MP4, M4V and MOV files with H.264 or HEVC video and AAC, MP3, AC-3, E-AC-3, ALAC or FLAC audio.
    ///   HEVC must carry the `hvc1` tag AVPlayer needs, or `dvh1` for Dolby Vision. AV1 plays too on a device whose
    ///   chip decodes it, and Dolby Vision on a device that shows it.
    /// - Everything else: HLS with fragmented MP4 segments, HEVC preferred, then AV1 where the device decodes it, then
    ///   H.264, so the server copies the video whenever it can and only the container changes.
    /// - Subtitles: text subtitles as WebVTT in the HLS manifest, MP4 text tracks as they are, and styled ASS, SSA and
    ///   image subtitles burned into the picture. There is no sidecar WebVTT, because AVPlayer can't show subtitles
    ///   from outside its stream; choosing such a subtitle makes the server repackage the video as HLS.
    ///
    /// Dolby Vision profile 7, from UHD Blu-rays, isn't listed: AVPlayer doesn't play it, so the server sends something
    /// it can.
    ///
    /// - Parameters:
    ///   - maxBitrate: The most bits per second to stream, from the user's quality setting, or nil for no cap.
    ///   - video: The AV1 and Dolby Vision the device plays.
    public static func serafin(maxBitrate: Int? = nil, video: VideoSupport = .current) -> DeviceProfile {
        let bitrate = maxBitrate ?? uncappedBitrate
        var playedCodecs = ["h264", "hevc"]
        var streamedCodecs = ["hevc", "h264"]
        var codecProfiles = [h264, hevc(dolbyVision: video.dolbyVision)]
        if let level = video.av1Level {
            playedCodecs.append("av1")
            streamedCodecs.insert("av1", at: 1)
            codecProfiles.append(av1(level: level, dolbyVision: video.dolbyVisionInAV1))
        }
        return DeviceProfile(
            codecProfiles: codecProfiles,
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                    container: "mp4,m4v,mov",
                    type: .video,
                    videoCodec: playedCodecs.joined(separator: ",")
                )
            ],
            maxStaticBitrate: bitrate,
            maxStreamingBitrate: bitrate,
            name: "Serafin",
            subtitleProfiles: [
                SubtitleProfile(format: "vtt", method: .hls),
                SubtitleProfile(format: "mov_text", method: .embed),
                SubtitleProfile(format: "ass", method: .encode),
                SubtitleProfile(format: "ssa", method: .encode),
                SubtitleProfile(format: "pgssub", method: .encode),
                SubtitleProfile(format: "dvdsub", method: .encode),
                SubtitleProfile(format: "dvbsub", method: .encode),
            ],
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: "aac,eac3,ac3",
                    container: "mp4",
                    context: .streaming,
                    enableSubtitlesInManifest: true,
                    isBreakOnNonKeyFrames: true,
                    maxAudioChannels: "8",
                    minSegments: 2,
                    type: .video,
                    videoCodec: streamedCodecs.joined(separator: ",")
                )
            ]
        )
    }

    /// The HDR formats every device Serafin runs on plays: HDR10 and HLG, and HDR10+ as HDR10.
    static let hdrRanges: [VideoRangeType] = [.sdr, .hdr10, .hdr10Plus, .hlg]

    /// The Dolby Vision a device that shows it plays: profile 5, and profile 8 over HDR10, HLG or SDR.
    static let dolbyVisionRanges: [VideoRangeType] = [
        .dovi, .doviWithHDR10, .doviWithHLG, .doviWithSDR, .doviWithHDR10Plus,
    ]

    /// H.264 that iOS decodes in hardware: 8-bit, progressive, SDR, up to level 5.2.
    private static let h264 = CodecProfile(
        codec: "h264",
        conditions: [
            ProfileCondition(condition: .notEquals, isRequired: false, property: .isAnamorphic, value: "true"),
            ProfileCondition(
                condition: .equalsAny,
                isRequired: false,
                property: .videoProfile,
                value: "high|main|baseline|constrained baseline"
            ),
            ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoLevel, value: "52"),
            ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoBitDepth, value: "8"),
            ProfileCondition(condition: .notEquals, isRequired: false, property: .isInterlaced, value: "true"),
            ProfileCondition(condition: .equalsAny, isRequired: false, property: .videoRangeType, value: "SDR"),
        ],
        type: .video
    )

    /// HEVC that AVPlayer plays: Main or Main 10 up to level 5.2 and 60 frames a second, tagged `hvc1`, in SDR,
    /// HDR10, HDR10+ or HLG, and on a device that shows Dolby Vision, profiles 5 and 8 tagged `hvc1` or `dvh1`.
    private static func hevc(dolbyVision: Bool) -> CodecProfile {
        let ranges = dolbyVision ? hdrRanges + dolbyVisionRanges : hdrRanges
        return CodecProfile(
            codec: "hevc",
            conditions: [
                ProfileCondition(condition: .notEquals, isRequired: false, property: .isAnamorphic, value: "true"),
                ProfileCondition(
                    condition: .equalsAny, isRequired: false, property: .videoProfile, value: "main|main 10"),
                ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoLevel, value: "156"),
                ProfileCondition(condition: .lessThanEqual, isRequired: true, property: .videoFramerate, value: "60"),
                ProfileCondition(condition: .notEquals, isRequired: false, property: .isInterlaced, value: "true"),
                ProfileCondition(
                    condition: .equalsAny,
                    isRequired: true,
                    property: .videoCodecTag,
                    value: dolbyVision ? "hvc1|dvh1" : "hvc1"
                ),
                ProfileCondition(
                    condition: .equalsAny,
                    isRequired: false,
                    property: .videoRangeType,
                    value: ranges.map(\.rawValue).joined(separator: "|")
                ),
            ],
            type: .video
        )
    }

    /// AV1 that the device's chip decodes: Main profile, 8-bit or 10-bit, up to `level`, in SDR, HDR10, HDR10+ or HLG,
    /// and with `dolbyVision`, Dolby Vision profile 10.
    private static func av1(level: Int, dolbyVision: Bool) -> CodecProfile {
        let ranges = dolbyVision ? hdrRanges + dolbyVisionRanges : hdrRanges
        return CodecProfile(
            codec: "av1",
            conditions: [
                ProfileCondition(condition: .notEquals, isRequired: false, property: .isAnamorphic, value: "true"),
                ProfileCondition(condition: .equalsAny, isRequired: false, property: .videoProfile, value: "main"),
                ProfileCondition(
                    condition: .lessThanEqual, isRequired: false, property: .videoLevel, value: String(level)),
                ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoBitDepth, value: "10"),
                ProfileCondition(
                    condition: .equalsAny,
                    isRequired: false,
                    property: .videoRangeType,
                    value: ranges.map(\.rawValue).joined(separator: "|")
                ),
            ],
            type: .video
        )
    }
}
