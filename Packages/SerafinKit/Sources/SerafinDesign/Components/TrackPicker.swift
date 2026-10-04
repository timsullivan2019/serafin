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

/// The audio and subtitle picker the player opens in a sheet: the audio tracks, then the subtitles with Off first,
/// each current choice checked.
public struct TrackPicker: View {
    private let audio: [TrackChoice]
    private let selectedAudio: Int?
    private let subtitles: [TrackChoice]
    private let selectedSubtitle: Int?
    private let selectAudio: (Int) -> Void
    private let selectSubtitle: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Creates the picker.
    ///
    /// - Parameters:
    ///   - audio: The audio tracks.
    ///   - selectedAudio: The ``TrackChoice/id`` of the audio playing.
    ///   - subtitles: The subtitle tracks.
    ///   - selectedSubtitle: The ``TrackChoice/id`` of the subtitles showing, or nil when they are off.
    ///   - selectAudio: Called with the ``TrackChoice/id`` of the audio picked.
    ///   - selectSubtitle: Called with the ``TrackChoice/id`` of the subtitles picked, or nil for Off.
    public init(
        audio: [TrackChoice],
        selectedAudio: Int?,
        subtitles: [TrackChoice],
        selectedSubtitle: Int?,
        selectAudio: @escaping (Int) -> Void,
        selectSubtitle: @escaping (Int?) -> Void
    ) {
        self.audio = audio
        self.selectedAudio = selectedAudio
        self.subtitles = subtitles
        self.selectedSubtitle = selectedSubtitle
        self.selectAudio = selectAudio
        self.selectSubtitle = selectSubtitle
    }

    public var body: some View {
        NavigationStack {
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
                    TrackRow(
                        title: String(localized: "Off", bundle: .module, comment: "Choice that turns subtitles off."),
                        detail: nil,
                        isSelected: selectedSubtitle == nil
                    ) {
                        selectSubtitle(nil)
                    }
                    ForEach(subtitles) { track in
                        TrackRow(title: track.title, detail: track.detail, isSelected: track.id == selectedSubtitle) {
                            selectSubtitle(track.id)
                        }
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
}

/// One track, with a checkmark when it is the current choice.
private struct TrackRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
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
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
    private struct TrackPickerSample: View {
        @State private var audio = 1
        @State private var subtitle: Int? = 4

        var body: some View {
            Color.black
                .ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    TrackPicker(
                        audio: [
                            TrackChoice(id: 1, title: "English", detail: "AAC · Stereo"),
                            TrackChoice(id: 2, title: "English", detail: "Dolby Digital Plus · 5.1"),
                            TrackChoice(id: 3, title: "French", detail: "AAC · Stereo"),
                        ],
                        selectedAudio: audio,
                        subtitles: [
                            TrackChoice(id: 4, title: "English", detail: "SDH"),
                            TrackChoice(id: 5, title: "Spanish"),
                        ],
                        selectedSubtitle: subtitle,
                        selectAudio: { audio = $0 },
                        selectSubtitle: { subtitle = $0 }
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
