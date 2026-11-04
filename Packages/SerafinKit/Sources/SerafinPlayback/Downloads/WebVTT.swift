import Foundation

/// One subtitle: when it shows and what it says, as plain text.
struct SubtitleCue: Equatable, Sendable {
    /// When it appears.
    var start: Duration
    /// When it goes.
    var end: Duration
    /// What it says, one line under another.
    var text: String
}

/// Reads the WebVTT files Jellyfin's subtitle endpoint sends, for adding subtitles to a downloaded copy.
///
/// The server's files are untrusted input, so the reader is forgiving and bounded: it reads only cue times and text,
/// keeps the text plain, and stops after ``maximumCues``. Styling, positions, regions and notes are left out, since a
/// copy's subtitles show in the player's own style.
enum WebVTT {
    /// The most cues read from one file, far more than any film has.
    static let maximumCues = 100_000
    /// The most bytes of text one subtitle keeps, which a 3GPP text sample can hold.
    static let maximumTextBytes = 4096

    /// The cues in `data`, in file order, with tags taken out and character references decoded. A cue with no text,
    /// or one that ends before it starts, is left out. Empty when `data` isn't WebVTT.
    static func cues(in data: Data) -> [SubtitleCue] {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.hasPrefix("WEBVTT") else { return [] }
        var cues: [SubtitleCue] = []
        var index = lines.startIndex
        while index < lines.endIndex, cues.count < maximumCues {
            // A block runs to the next blank line. Only one with a timing line is a cue.
            var block: [Substring] = []
            while index < lines.endIndex, !lines[index].allSatisfy(\.isWhitespace) {
                block.append(lines[index])
                index += 1
            }
            index += 1
            guard let timing = block.firstIndex(where: { $0.contains("-->") }),
                let (start, end) = times(block[timing]), end > start
            else { continue }
            let body = block[(timing + 1)...].map { plainText($0) }.joined(separator: "\n")
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: limited(trimmed)))
        }
        return cues
    }

    /// The start and end of a timing line, such as `00:01:02.500 --> 00:01:04.000 line:90%`.
    static func times(_ line: Substring) -> (Duration, Duration)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
            let start = time(parts[0].trimmingCharacters(in: .whitespaces)),
            let endField = parts[1].split(whereSeparator: \.isWhitespace).first,
            let end = time(String(endField))
        else { return nil }
        return (start, end)
    }

    /// A WebVTT timestamp, `hh:mm:ss.ttt` or `mm:ss.ttt`, with up to four digits of hours.
    static func time(_ text: String) -> Duration? {
        let fields = text.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2 || fields.count == 3 else { return nil }
        let secondsField = fields[fields.count - 1].split(separator: ".", omittingEmptySubsequences: false)
        guard secondsField.count == 2, secondsField[0].count == 2, secondsField[1].count == 3,
            let seconds = number(secondsField[0]), seconds < 60,
            let milliseconds = number(secondsField[1]),
            let minutes = number(fields[fields.count - 2]), minutes < 60
        else { return nil }
        var hours: Int64 = 0
        if fields.count == 3 {
            guard fields[0].count <= 4, let parsed = number(fields[0]) else { return nil }
            hours = parsed
        }
        return .milliseconds(((hours * 60 + minutes) * 60 + seconds) * 1000 + milliseconds)
    }

    /// The number `digits` writes, when it's nothing but ASCII digits, at most nine of them.
    private static func number(_ digits: Substring) -> Int64? {
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int64(digits)
    }

    /// `line` without its tags, such as `<i>` or `<v Speaker>`, and with its character references decoded.
    static func plainText(_ line: Substring) -> String {
        var plain = ""
        var inTag = false
        for character in line {
            switch character {
            case "<": inTag = true
            case ">" where inTag: inTag = false
            default:
                if !inTag { plain.append(character) }
            }
        }
        return decodingReferences(plain)
    }

    /// The named references WebVTT defines, and the ones subtitle files commonly use.
    private static let references: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "lrm": "\u{200E}",
        "rlm": "\u{200F}",
    ]

    /// `text` with character references such as `&amp;` and `&#233;` decoded. Anything else stays as it is.
    static func decodingReferences(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var decoded = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            decoded += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            guard let semicolon = rest[afterAmpersand...].prefix(12).firstIndex(of: ";") else {
                decoded += "&"
                rest = rest[afterAmpersand...]
                continue
            }
            let name = rest[afterAmpersand..<semicolon]
            if let character = character(named: name) {
                decoded += character
                rest = rest[rest.index(after: semicolon)...]
            } else {
                decoded += "&"
                rest = rest[afterAmpersand...]
            }
        }
        return decoded + rest
    }

    /// The character a reference's name stands for, such as `amp` or `#x41`, or nil when it stands for none.
    private static func character(named name: Substring) -> String? {
        if let named = references[String(name)] {
            return named
        }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits)
        }
        guard let value, value != 0, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    /// `text` cut to ``maximumTextBytes`` of UTF-8, at a character boundary.
    private static func limited(_ text: String) -> String {
        guard text.utf8.count > maximumTextBytes else { return text }
        var kept = ""
        for character in text {
            guard kept.utf8.count + character.utf8.count <= maximumTextBytes else { break }
            kept.append(character)
        }
        return kept
    }
}

/// Subtitles as a 3GPP text track shows them: one sample at a time, from the start of the video.
enum TimedText {
    /// A stretch of time that shows one text, or none when it's empty.
    struct Stretch: Equatable, Sendable {
        /// When it starts.
        var start: Duration
        /// When it ends.
        var end: Duration
        /// What shows, or nothing between subtitles.
        var text: String
    }

    /// `cues` as consecutive stretches from the start of the video to the end of the last cue. Cues that overlap
    /// share the stretches where they do, their texts one under another in file order, and the gaps between cues are
    /// empty stretches.
    static func stretches(of cues: [SubtitleCue]) -> [Stretch] {
        guard !cues.isEmpty else { return [] }
        let boundaries = Set(cues.flatMap { [$0.start, $0.end] } + [.zero]).filter { $0 >= .zero }.sorted()
        let byStart = cues.indices.sorted { (cues[$0].start, $0) < (cues[$1].start, $1) }
        var next = byStart.startIndex
        var showing: [Int] = []
        var stretches: [Stretch] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            showing.removeAll { cues[$0].end <= start }
            while next < byStart.endIndex, cues[byStart[next]].start <= start {
                if cues[byStart[next]].end > start {
                    showing.append(byStart[next])
                }
                next += 1
            }
            let text = showing.sorted().map { cues[$0].text }.joined(separator: "\n")
            if let last = stretches.last, last.text == text, last.end == start {
                stretches[stretches.count - 1].end = end
            } else {
                stretches.append(Stretch(start: start, end: end, text: text))
            }
        }
        return stretches
    }

    /// A 3GPP text sample showing `text`: its length in bytes, then the text as UTF-8.
    static func sample(_ text: String) -> Data {
        let bytes = Array(text.utf8.prefix(Int(UInt16.max)))
        let length = UInt16(bytes.count)
        return Data([UInt8(length >> 8), UInt8(length & 0xFF)] + bytes)
    }
}
