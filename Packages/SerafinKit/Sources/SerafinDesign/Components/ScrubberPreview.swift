import SwiftUI

/// A chapter of the video playing, as the scrubber marks it: a tick in the track where it starts, and its name in the
/// preview while the knob is inside it.
public struct ScrubberChapter: Hashable, Sendable {
    /// The chapter's name.
    public var name: String
    /// Where it starts.
    public var start: Duration

    /// Creates a chapter.
    public init(name: String, start: Duration) {
        self.name = name
        self.start = start
    }
}

/// The thumbnails the scrubber's preview shows of the frame under the finger, such as the trickplay thumbnails a
/// Jellyfin server makes.
public struct ScrubberThumbnails {
    /// A thumbnail's width over its height.
    public var aspectRatio: CGFloat
    /// The thumbnail of the frame at a position, or nil while none has loaded. The preview reads it as it draws, so
    /// observable state read here draws the preview again when it changes, as when a thumbnail arrives.
    public var image: @MainActor (Duration) -> Image?
    /// Starts loading the thumbnails around a position, as a drag moves along the track. It's called on every move,
    /// so it returns at once.
    public var prepare: @MainActor (Duration) -> Void

    /// Creates the thumbnails.
    ///
    /// - Parameters:
    ///   - aspectRatio: A thumbnail's width over its height.
    ///   - image: The thumbnail of the frame at a position, or nil while none has loaded.
    ///   - prepare: Starts loading the thumbnails around a position.
    public init(
        aspectRatio: CGFloat,
        image: @escaping @MainActor (Duration) -> Image?,
        prepare: @escaping @MainActor (Duration) -> Void = { _ in }
    ) {
        self.aspectRatio = aspectRatio
        self.image = image
        self.prepare = prepare
    }
}

/// What floats above the scrubber's knob while a finger drags it, as in the TV app: a glass-framed thumbnail of the
/// frame under the finger, with the time underneath, and the chapter's name when the knob is inside one. A video
/// without thumbnails shows the time and chapter alone in the same glass, so the gesture feels the same.
///
/// With a thumbnail it's as wide as it's offered, the thumbnail filling that width; without one it's as wide as its
/// text. The thumbnail keeps its video's shape, from square to 2.5 times as wide as it's tall, and shows a dark frame
/// until it loads. The whole preview is decorative and hidden from VoiceOver, which hears the scrubber's own value.
/// ``PlayerControls`` shows it while the scrubber is dragged. Always dark, like the rest of the player.
public struct ScrubberPreview: View {
    /// The narrowest and widest shapes a thumbnail's frame takes, as width over height.
    static let aspectRatios: ClosedRange<CGFloat> = 1...2.5

    private let time: String
    private let chapter: String?
    private let showsThumbnail: Bool
    private let thumbnail: Image?
    private let aspectRatio: CGFloat

    /// Creates the preview.
    ///
    /// - Parameters:
    ///   - position: The time under the finger.
    ///   - chapter: The name of the chapter the knob is inside, or nil.
    ///   - showsThumbnail: Whether the video has thumbnails, which show above the time.
    ///   - thumbnail: The thumbnail of the frame at `position`, or nil while it loads.
    ///   - aspectRatio: A thumbnail's width over its height.
    public init(
        position: Duration,
        chapter: String? = nil,
        showsThumbnail: Bool,
        thumbnail: Image? = nil,
        aspectRatio: CGFloat = 16 / 9
    ) {
        self.time = ScrubberMath.timecode(position)
        self.chapter = chapter
        self.showsThumbnail = showsThumbnail
        self.thumbnail = thumbnail
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        VStack(spacing: Spacing.xxSmall) {
            if showsThumbnail {
                thumbnailFrame
            }
            caption
        }
        .padding(Spacing.xxSmall)
        .glassEffect(.regular, in: .rounded(.medium))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    /// The thumbnail in its rounded frame, filling the width it's offered at the video's shape.
    private var thumbnailFrame: some View {
        Color.black.opacity(0.35)
            .aspectRatio(
                min(
                    max(aspectRatio.isFinite ? aspectRatio : 16 / 9, Self.aspectRatios.lowerBound),
                    Self.aspectRatios.upperBound),
                contentMode: .fit
            )
            .frame(maxWidth: .infinity)
            .overlay {
                if let thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(.rounded(.small))
    }

    /// The chapter's name over the time.
    private var caption: some View {
        VStack(spacing: 0) {
            if let chapter {
                Text(chapter)
                    .typography(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(time)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(.horizontal, showsThumbnail ? Spacing.xxSmall : Spacing.xSmall)
        .padding(.vertical, Spacing.xxSmall)
        // Lifted off bright video, as the player's title is.
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }
}

/// Places the scrubber's preview above the knob: its bottom ``ScrubberMath/previewGap`` above the scrubber, centred
/// on the knob, and moved in to stay ``ScrubberMath/previewMargin`` inside the edges. The preview is offered the width
/// ``ScrubberMath/previewWidth(containerWidth:isRegular:)`` gives for the space, and placed with no lag behind the
/// knob, since its size is known as it's placed.
struct ScrubberPreviewPlacement: Layout {
    /// Where the knob is across, in the placement's space.
    var knob: CGFloat
    /// The top of the scrubber, in the placement's space.
    var top: CGFloat
    /// Whether the space is regular width, as on iPad, where the preview may be wider.
    var isRegular: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ScrubberMath.previewWidth(containerWidth: bounds.width, isRegular: isRegular)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let origin = ScrubberMath.previewOrigin(of: size, knob: knob, top: top, width: bounds.width)
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
        }
    }
}

/// The chapter starts on the scrubber's track, as narrow gaps cut out of it. Drawn with the `destinationOut` blend
/// mode inside the track's compositing group, so the glass behind shows through, filled or not.
struct ChapterTicks: View {
    let fractions: [Double]

    var body: some View {
        GeometryReader { proxy in
            ForEach(fractions, id: \.self) { fraction in
                Rectangle()
                    .frame(width: ScrubberMath.tickWidth, height: proxy.size.height)
                    .position(x: proxy.size.width * fraction, y: proxy.size.height / 2)
            }
        }
        .blendMode(.destinationOut)
        .accessibilityHidden(true)
    }
}

extension ScrubberMath {
    /// The space between the preview and the top of the scrubber.
    static let previewGap = Spacing.small
    /// The closest the preview comes to the edges of the player.
    static let previewMargin = Spacing.medium
    /// The narrowest preview.
    static let minimumPreviewWidth: CGFloat = 160
    /// The width of a chapter tick on the track.
    static let tickWidth: CGFloat = 2
    /// The least room kept between chapter ticks, and between a tick and either end of the track. A tick closer to
    /// the one before is left out.
    static let tickSpacing: CGFloat = 6

    /// How wide the preview is in a player `containerWidth` points wide: a little over a quarter of it, at least 160
    /// points, and at most 320 on iPhone or 480 on iPad.
    static func previewWidth(containerWidth: CGFloat, isRegular: Bool) -> CGFloat {
        let widest: CGFloat = isRegular ? 480 : 320
        let room = max(containerWidth - 2 * previewMargin, 0)
        return min(max(containerWidth * 0.28, minimumPreviewWidth), widest, room)
    }

    /// Where a preview of `size` goes, its top-leading corner: centred on `knob` across, its bottom
    /// ``previewGap`` above `top`, and moved in to stay ``previewMargin`` inside a space `width` wide, or centred in
    /// it when it's too narrow for that.
    static func previewOrigin(of size: CGSize, knob: CGFloat, top: CGFloat, width: CGFloat) -> CGPoint {
        let leading = previewMargin
        let trailing = width - previewMargin - size.width
        let centred = knob - size.width / 2
        let x = trailing < leading ? (width - size.width) / 2 : min(max(centred, leading), trailing)
        return CGPoint(x: x, y: top - previewGap - size.height)
    }

    /// The chapter `position` is inside: the last to start at or before it, or nil before the first.
    static func chapter(at position: Duration, in chapters: [ScrubberChapter]) -> ScrubberChapter? {
        chapters.last { $0.start <= position }
    }

    /// Where the chapter ticks go on a track `trackWidth` points wide, as fractions of the way through `duration`:
    /// one at each chapter's start, but none within ``tickSpacing`` of either end or of the tick before.
    static func tickFractions(for chapters: [ScrubberChapter], in duration: Duration, trackWidth: CGFloat) -> [Double] {
        guard duration > .zero, trackWidth > 2 * tickSpacing else { return [] }
        let starts = chapters.map { fraction(of: $0.start, in: duration) }.sorted()
        var ticks: [Double] = []
        for start in starts {
            let x = start * trackWidth
            guard x >= tickSpacing, x <= trackWidth - tickSpacing else { continue }
            if let last = ticks.last, x - last * trackWidth < tickSpacing { continue }
            ticks.append(start)
        }
        return ticks
    }
}

#if DEBUG
    private struct ScrubberPreviewSample: View {
        var showsThumbnail = true
        var chapter: String? = "Opening Titles"
        private let card = MockMedia.movies[1]

        var body: some View {
            ScrubberPreview(
                position: .seconds(372),
                chapter: chapter,
                showsThumbnail: showsThumbnail,
                thumbnail: MockMedia.backdropImage(for: card)
            )
            .frame(width: 240)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                (MockMedia.backdropImage(for: card) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
        }
    }

    #Preview("Light") {
        ScrubberPreviewSample()
    }

    #Preview("Dark") {
        ScrubberPreviewSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ScrubberPreviewSample()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("Time only, light") {
        ScrubberPreviewSample(showsThumbnail: false, chapter: nil)
    }

    #Preview("Time and chapter, dark") {
        ScrubberPreviewSample(showsThumbnail: false)
            .preferredColorScheme(.dark)
    }

    #Preview("Loading") {
        ScrubberPreview(position: .seconds(5_940), showsThumbnail: true)
            .frame(width: 240)
            .padding()
            .background(.black)
    }
#endif
