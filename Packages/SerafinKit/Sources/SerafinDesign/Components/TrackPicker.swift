import SwiftUI

/// An audio or subtitle track the viewer can pick.
public struct TrackChoice: Identifiable, Hashable, Sendable {
    /// The server's number for the track.
    public var id: Int
    /// The track's name, such as "English".
    public var title: String
    /// More about it, such as "Dolby Digital 5.1".
    public var detail: String?

    /// Creates a track choice.
    public init(id: Int, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Subtitles the picker can show as chosen.
public enum SubtitlePick: Hashable, Sendable {
    /// None.
    case off
    /// The subtitle track with this ``TrackChoice/id``.
    case track(Int)
    /// Subtitles the device generates from the audio.
    case generated
}

/// The audio and subtitle picker the player opens in a sheet: the audio tracks, then the subtitles with Off first and
/// the device's generated subtitles last, where it offers them. What's showing is checked, and a pick still on its
/// way shows a spinner. Under its title it says how the video reaches the player, such as "Direct play".
public struct TrackPicker: View {
    private let delivery: PlaybackDelivery?
    private let audio: [TrackChoice]
    private let selectedAudio: Int?
    private let subtitles: [TrackChoice]
    private let generatedSubtitles: TrackChoice?
    private let selectedSubtitles: SubtitlePick
    private let pendingSubtitles: SubtitlePick?
    private let selectAudio: (Int) -> Void
    private let selectSubtitles: (SubtitlePick) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Creates the picker.
    ///
    /// - Parameters:
    ///   - delivery: How the video reaches the player, shown under the title, or nil while that isn't known.
    ///   - audio: The audio tracks.
    ///   - selectedAudio: The ``TrackChoice/id`` of the audio playing.
    ///   - subtitles: The subtitle tracks.
    ///   - generatedSubtitles: The device's generated subtitles, as their row shows them, or nil when it offers none.
    ///     Their ``TrackChoice/id`` isn't used.
    ///   - selectedSubtitles: The subtitles showing.
    ///   - pendingSubtitles: Subtitles picked that are still on their way, or nil.
    ///   - selectAudio: Called with the ``TrackChoice/id`` of the audio picked.
    ///   - selectSubtitles: Called with the subtitles picked.
    public init(
        delivery: PlaybackDelivery? = nil,
        audio: [TrackChoice],
        selectedAudio: Int?,
        subtitles: [TrackChoice],
        generatedSubtitles: TrackChoice? = nil,
        selectedSubtitles: SubtitlePick,
        pendingSubtitles: SubtitlePick? = nil,
        selectAudio: @escaping (Int) -> Void,
        selectSubtitles: @escaping (SubtitlePick) -> Void
    ) {
        self.delivery = delivery
        self.audio = audio
        self.selectedAudio = selectedAudio
        self.subtitles = subtitles
        self.generatedSubtitles = generatedSubtitles
        self.selectedSubtitles = selectedSubtitles
        self.pendingSubtitles = pendingSubtitles
        self.selectAudio = selectAudio
        self.selectSubtitles = selectSubtitles
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                list
                    .onAppear {
                        // The subtitles showing are in view as the sheet opens, even far down a long list.
                        if selectedSubtitles != .off {
                            scroller.scrollTo(selectedSubtitles, anchor: .center)
                        }
                    }
            }
            .navigationTitle(
                String(
                    localized: "Audio and Subtitles",
                    bundle: .module,
                    comment: "Button that opens the audio and subtitle picker."
                )
            )
            .modifier(DeliverySubtitle(delivery: delivery))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            if !audio.isEmpty {
                Section(String(localized: "Audio", bundle: .module, comment: "Heading of the audio tracks.")) {
                    ForEach(audio) { track in
                        TrackRow(title: track.title, detail: track.detail, isSelected: track.id == selectedAudio) {
                            selectAudio(track.id)
                        }
                    }
                }
            }
            Section(String(localized: "Subtitles", bundle: .module, comment: "Heading of the subtitle tracks.")) {
                subtitleRow(
                    .off,
                    title: String(localized: "Off", bundle: .module, comment: "Choice that turns subtitles off."),
                    detail: nil
                )
                ForEach(subtitles) { track in
                    subtitleRow(.track(track.id), title: track.title, detail: track.detail)
                }
                if let generatedSubtitles {
                    subtitleRow(.generated, title: generatedSubtitles.title, detail: generatedSubtitles.detail)
                }
            }
        }
    }

    private func subtitleRow(_ pick: SubtitlePick, title: String, detail: String?) -> some View {
        TrackRow(
            title: title,
            detail: detail,
            isSelected: pick == selectedSubtitles,
            isPending: pick == pendingSubtitles && pick != selectedSubtitles
        ) {
            selectSubtitles(pick)
        }
        .id(pick)
    }
}

/// How the video reaches the player, under the picker's title, once it is known.
private struct DeliverySubtitle: ViewModifier {
    let delivery: PlaybackDelivery?

    func body(content: Content) -> some View {
        if let delivery {
            content.navigationSubtitle(delivery.title)
        } else {
            content
        }
    }
}

/// One track, with a checkmark when it is the current choice, or a spinner while it's on its way.
private struct TrackRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    var isPending = false
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.textPrimary)
                    if let detail {
                        Text(detail)
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if isPending {
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            isPending ? String(localized: "Loading", bundle: .module, comment: "Spoken while content loads.") : ""
        )
    }
}

#if DEBUG
    private struct TrackPickerSample: View {
        @State private var audio = 1
        @State private var subtitles = SubtitlePick.track(4)

        var body: some View {
            Color.black
                .ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    TrackPicker(
                        delivery: .repackaged,
                        audio: [
                            TrackChoice(id: 1, title: "English", detail: "AAC · Stereo"),
                            TrackChoice(id: 2, title: "English", detail: "Dolby Digital Plus · 5.1"),
                            TrackChoice(id: 3, title: "French", detail: "AAC · Stereo"),
                        ],
                        selectedAudio: audio,
                        subtitles: [
                            TrackChoice(id: 4, title: "English", detail: "SDH · SRT"),
                            TrackChoice(id: 5, title: "English", detail: "PGS"),
                            TrackChoice(id: 6, title: "Spanish", detail: "SRT"),
                        ],
                        generatedSubtitles: TrackChoice(
                            id: 0, title: "Generated", detail: "English · Created from the audio"),
                        selectedSubtitles: subtitles,
                        pendingSubtitles: .track(5),
                        selectAudio: { audio = $0 },
                        selectSubtitles: { subtitles = $0 }
                    )
                    .presentationDetents([.medium, .large])
                }
        }
    }

    #Preview("Light") {
        TrackPickerSample()
    }

    #Preview("Dark") {
        TrackPickerSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TrackPickerSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
