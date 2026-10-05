import SwiftUI

/// A strip of letters along the trailing edge of a long grid sorted by name, like the index in Contacts: touch it
/// or drag along it to jump to the titles under a letter.
///
/// It ticks as the finger passes each letter. When the strip is too short for every letter, it shows every other
/// one with a dot between, as the system index does, and a drag still reaches each letter. VoiceOver reads it as one
/// adjustable element: swipe up or down to move through the letters.
public struct LetterIndex: View {
    /// "#" for titles that start with a digit or a symbol, then A to Z.
    public static let alphabet: [String] = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    private let letters: [String]
    private let jump: (String) -> Void
    @State private var touched: String?
    @State private var spoken = 0
    @State private var available: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var rowHeight = 14.0

    /// Creates an index.
    ///
    /// - Parameters:
    ///   - letters: The letters, top to bottom. The grid's order decides it: A to Z, or Z to A when sorted backwards.
    ///   - jump: Called with each letter the finger reaches.
    public init(letters: [String] = LetterIndex.alphabet, jump: @escaping (String) -> Void) {
        self.letters = letters
        self.jump = jump
    }

    public var body: some View {
        Color.clear
            .frame(width: 20)
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                available = $0
            }
            .overlay { strip }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var strip: some View {
        let rows = LetterIndexMath.rows(for: letters, capacity: Int(available / rowHeight))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(verbatim: row)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 20, height: rowHeight)
            }
        }
        .foregroundStyle(.tint)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    reach(
                        LetterIndexMath.letter(
                            at: value.location.y, height: CGFloat(rows.count) * rowHeight, count: letters.count))
                }
                .onEnded { _ in touched = nil }
        )
        .sensoryFeedback(trigger: touched) { _, letter in letter == nil ? nil : .selection }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Index", bundle: .module, comment: "Spoken name of the letter index."))
        .accessibilityValue(letters.indices.contains(spoken) ? letters[spoken] : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: spoken = min(spoken + 1, letters.count - 1)
            case .decrement: spoken = max(spoken - 1, 0)
            @unknown default: return
            }
            jump(letters[spoken])
        }
    }

    private func reach(_ index: Int) {
        let letter = letters[index]
        guard letter != touched else { return }
        touched = letter
        spoken = index
        jump(letter)
    }
}

/// The arithmetic behind the letter index.
enum LetterIndexMath {
    /// The position in a list of `count` letters spread evenly down a strip `height` points tall, under `y`.
    static func letter(at y: CGFloat, height: CGFloat, count: Int) -> Int {
        guard height > 0, count > 0 else { return 0 }
        return min(max(Int(y / height * CGFloat(count)), 0), count - 1)
    }

    /// The rows to show when only `capacity` fit: every letter when they all fit, otherwise letters at even steps with
    /// a dot between each pair, always keeping the first and the last.
    static func rows(for letters: [String], capacity: Int) -> [String] {
        guard capacity < letters.count, letters.count > 2 else { return letters }
        // Each shown letter but the last takes a dot after it, so k letters need 2k - 1 rows.
        let shown = max((capacity + 1) / 2, 2)
        let step = Double(letters.count - 1) / Double(shown - 1)
        var rows: [String] = []
        for position in 0..<shown {
            if position > 0 { rows.append("•") }
            rows.append(letters[Int((Double(position) * step).rounded())])
        }
        return rows
    }
}

#if DEBUG
    private struct LetterIndexSample: View {
        @State private var letter = "–"

        var body: some View {
            HStack {
                Text(verbatim: letter)
                    .font(.system(size: 96, weight: .bold))
                    .frame(maxWidth: .infinity)
                LetterIndex { letter = $0 }
                    .padding(.vertical, Spacing.large)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        LetterIndexSample()
    }

    #Preview("Dark, short") {
        LetterIndexSample()
            .frame(height: 260)
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        LetterIndexSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
