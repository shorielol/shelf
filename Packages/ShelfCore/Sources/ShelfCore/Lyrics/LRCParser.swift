import Foundation

/// Parses LRC lyrics, including repeated timestamps, `[offset:]` and enhanced `<mm:ss.xx>` word tags.
public enum LRCParser {
    /// How long a line without a successor stays lit when the track duration is unknown.
    static let trailingLineSeconds: TimeInterval = 5
    /// Per-character pace for interpolated words, so a short line before a long gap doesn't crawl.
    static let maxSecondsPerCharacter: TimeInterval = 0.12
    static let minimumWordSeconds: TimeInterval = 0.25

    public static func parse(_ text: String, duration: TimeInterval? = nil) -> [LyricLine] {
        var offset: TimeInterval = 0
        var raw: [(start: TimeInterval, body: String)] = []

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
            let line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            if let value = metadata("offset", in: line), let millis = Double(value) {
                offset = millis / 1000
                continue
            }
            let (stamps, body) = leadingTimestamps(line)
            for stamp in stamps { raw.append((stamp, body)) }
        }

        let sorted = raw.enumerated()
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
            .map(\.element)

        return sorted.enumerated().map { index, entry in
            let start = max(0, entry.start - offset)
            let nextStart = index + 1 < sorted.count ? max(0, sorted[index + 1].start - offset) : nil
            let end = nextStart ?? max(start, duration ?? (start + trailingLineSeconds))
            return makeLine(id: index, start: start, end: max(end, start), body: entry.body, offset: offset)
        }
    }

    // MARK: - Pieces

    private static func metadata(_ key: String, in line: Substring) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        let inner = line.dropFirst().dropLast()
        guard let colon = inner.firstIndex(of: ":") else { return nil }
        guard inner[..<colon].lowercased() == key else { return nil }
        return inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    private static func leadingTimestamps(_ line: Substring) -> ([TimeInterval], String) {
        var rest = line
        var stamps: [TimeInterval] = []
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            let inner = rest[rest.index(after: rest.startIndex)..<close]
            guard let time = timestamp(inner) else { break }
            stamps.append(time)
            rest = rest[rest.index(after: close)...]
        }
        return (stamps, rest.trimmingCharacters(in: .whitespaces))
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx`.
    static func timestamp(_ text: Substring) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        guard let seconds = Double(parts[1].replacingOccurrences(of: ",", with: ".")), seconds >= 0, seconds < 60 else { return nil }
        return Double(minutes) * 60 + seconds
    }

    private static func makeLine(id: Int, start: TimeInterval, end: TimeInterval, body: String, offset: TimeInterval) -> LyricLine {
        if let tagged = taggedWords(body, lineEnd: end, offset: offset) {
            let text = tagged.map(\.text).joined(separator: " ")
            return LyricLine(id: id, start: start, end: end, text: text, words: tagged, hasWordTiming: true)
        }
        return LyricLine(id: id, start: start, end: end, text: body, words: interpolatedWords(body, start: start, end: end), hasWordTiming: false)
    }

    private static func taggedWords(_ body: String, lineEnd: TimeInterval, offset: TimeInterval) -> [LyricWord]? {
        guard body.contains("<") else { return nil }
        var pieces: [(TimeInterval, String)] = []
        var rest = Substring(body)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            guard let time = timestamp(rest[rest.index(after: open)..<close]) else { return nil }
            let after = rest[rest.index(after: close)...]
            let nextOpen = after.firstIndex(of: "<") ?? after.endIndex
            let word = after[..<nextOpen].trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { pieces.append((max(0, time - offset), word)) }
            rest = after[nextOpen...]
        }
        guard !pieces.isEmpty else { return nil }
        return pieces.enumerated().map { index, piece in
            let next = index + 1 < pieces.count ? pieces[index + 1].0 : lineEnd
            return LyricWord(text: piece.1, start: piece.0, end: max(piece.0, min(next, lineEnd)))
        }
    }

    private static func interpolatedWords(_ body: String, start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        let tokens = body.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        let characters = tokens.reduce(0) { $0 + $1.count }
        let paced = Double(characters) * maxSecondsPerCharacter + Double(tokens.count) * minimumWordSeconds
        let span = min(max(0, end - start), paced)
        var cursor = start
        return tokens.map { token in
            let share = span * Double(token.count) / Double(max(characters, 1))
            defer { cursor += share }
            return LyricWord(text: token, start: cursor, end: cursor + share)
        }
    }
}
