import SwiftUI

/// A detail screen's media badges, such as 4K, Dolby Vision, Dolby Atmos and SDH, in the Apple TV app's style: small
/// uppercase labels in thin outlined capsules, with no fill, in the order they're given.
public struct MediaBadgeRow: View {
    private let badges: [String]

    /// Creates a row of badges.
    ///
    /// - Parameter badges: The badges' labels, in order: resolution, range, audio, then accessibility.
    public init(badges: [String]) {
        self.badges = badges
    }

    public var body: some View {
        // Wraps onto more lines at large text sizes rather than squeezing.
        FlowingBadges(spacing: Spacing.xSmall) {
            ForEach(badges, id: \.self) { badge in
                MediaBadge(badge)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badges.formatted(.list(type: .and, width: .narrow)))
    }
}

/// One badge: an 11-point uppercase label in a 1-point outlined capsule.
public struct MediaBadge: View {
    private let label: String
    @ScaledMetric(relativeTo: .caption2) private var size = 11.0

    /// Creates a badge.
    ///
    /// - Parameter label: The badge's text, such as "4K".
    public init(_ label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label.uppercased())
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                Capsule().strokeBorder(.textSecondary, lineWidth: 1)
            }
    }
}

/// Lays badges out in lines, starting a new line when the next badge wouldn't fit, centred like the hero's text.
private struct FlowingBadges: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(for: subviews, width: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            var x = bounds.midX - line.width / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let added = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if added > width, !line.indices.isEmpty {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
        }
        if !line.indices.isEmpty { lines.append(line) }
        return lines
    }
}

/// A 16:9 picture with a title and a line under it, for a detail screen's trailers and chapters. A play symbol sits
/// on the picture, since tapping one plays it.
public struct ThumbnailCard: View {
    private let title: String
    private let caption: String?
    private let image: Image?
    private let number: Int?

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - title: The trailer's or chapter's name.
    ///   - caption: A line under it, such as a chapter's start time.
    ///   - image: The picture, or nil while it loads or when there is none.
    ///   - number: For a chapter that has no picture, its number, drawn large on a dark tile in its place.
    public init(title: String, caption: String?, image: Image?, number: Int? = nil) {
        self.title = title
        self.caption = caption
        self.image = image
        self.number = number
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    ZStack {
                        if let image {
                            Rectangle().fill(.surface)
                            image.resizable().scaledToFill().transition(.opacity)
                        } else if let number {
                            NumberTile(number: number)
                        } else {
                            Rectangle().fill(.surface)
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: image != nil)
                }
                .overlay {
                    if image != nil || number == nil {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(Spacing.small)
                            .background(.black.opacity(0.35), in: .circle)
                    }
                }
                .clipShape(.rounded(.small))
                .cardHoverEffect()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .modifier(CardTitleLines(standard: 2))
                if let caption {
                    Text(caption)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, caption].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// A chapter's number on a dark tile, standing in for a picture the file doesn't have.
private struct NumberTile: View {
    let number: Int

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.11))
            Text(number, format: .number)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .minimumScaleFactor(0.5)
                .padding(Spacing.small)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
    private struct MediaBadgesSample: View {
        var body: some View {
            VStack(spacing: Spacing.large) {
                MediaBadgeRow(badges: ["4K", "Dolby Vision", "Dolby Atmos", "5.1", "SDH"])
                    .environment(\.colorScheme, .dark)
                    .padding()
                    .background(.black)
                MediaBadgeRow(badges: ["HD", "HDR", "Lossless", "CC"])
                HStack(alignment: .top, spacing: Spacing.small) {
                    ThumbnailCard(
                        title: "Chapter 3", caption: "12:40", image: MockMedia.backdropImage(for: MockMedia.movies[2]))
                    ThumbnailCard(title: "Chapter 4", caption: "18:05", image: nil, number: 4)
                }
            }
            .padding()
            .background(Color.background)
        }
    }

    #Preview("Light") {
        MediaBadgesSample()
    }

    #Preview("Dark") {
        MediaBadgesSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        MediaBadgesSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
