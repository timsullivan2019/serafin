import JellyfinAPI

extension DeviceProfile {
    /// The bitrate Serafin asks for when the user sets no cap: 120 Mbps, above any Blu-ray remux.
    public static let uncappedBitrate = 120_000_000

    /// What Serafin's AVPlayer can play as it is, and what the server should make when it can't.
    ///
    /// - Direct play: MP4, M4V and MOV files with H.264 or HEVC video and AAC, MP3, AC-3, E-AC-3, ALAC or FLAC audio.
    ///   HEVC must carry the `hvc1` tag AVPlayer needs. AV1 and Dolby Vision are left to the server for now.
    /// - Everything else: HLS with fragmented MP4 segments, HEVC preferred over H.264, so the server copies the
    ///   video whenever it can and only the container changes.
    /// - Subtitles: text subtitles as WebVTT in the HLS manifest, MP4 text tracks as they are, and styled ASS, SSA and
    ///   image subtitles burned into the picture. There is no sidecar WebVTT, because AVPlayer can't show subtitles
    ///   from outside its stream; choosing such a subtitle makes the server repackage the video as HLS.
    ///
    /// - Parameter maxBitrate: The most bits per second to stream, from the user's quality setting, or nil for no
    ///   cap.
    public static func serafin(maxBitrate: Int? = nil) -> DeviceProfile {
        let bitrate = maxBitrate ?? uncappedBitrate
        return DeviceProfile(
            codecProfiles: [h264, hevc],
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: "aac,mp3,ac3,eac3,alac,flac",
                    container: "mp4,m4v,mov",
                    type: .video,
                    videoCodec: "h264,hevc"
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
                    videoCodec: "hevc,h264"
                )
            ]
        )
    }

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
    /// HDR10, HDR10+ or HLG. Dolby Vision waits for a later release.
    private static let hevc = CodecProfile(
        codec: "hevc",
        conditions: [
            ProfileCondition(condition: .notEquals, isRequired: false, property: .isAnamorphic, value: "true"),
            ProfileCondition(condition: .equalsAny, isRequired: false, property: .videoProfile, value: "main|main 10"),
            ProfileCondition(condition: .lessThanEqual, isRequired: false, property: .videoLevel, value: "156"),
            ProfileCondition(condition: .lessThanEqual, isRequired: true, property: .videoFramerate, value: "60"),
            ProfileCondition(condition: .notEquals, isRequired: false, property: .isInterlaced, value: "true"),
            ProfileCondition(condition: .equalsAny, isRequired: true, property: .videoCodecTag, value: "hvc1"),
            ProfileCondition(
                condition: .equalsAny,
                isRequired: false,
                property: .videoRangeType,
                value: "SDR|HDR10|HDR10Plus|HLG"
            ),
        ],
        type: .video
    )
}
