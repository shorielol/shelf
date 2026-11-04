import Foundation

public struct LyricWord: Sendable, Equatable, Hashable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct LyricLine: Sendable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let words: [LyricWord]
    /// True when the source carried per-word timestamps (enhanced LRC); otherwise words are interpolated.
    public let hasWordTiming: Bool

    public var isBreak: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    public init(id: Int, start: TimeInterval, end: TimeInterval, text: String, words: [LyricWord], hasWordTiming: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.hasWordTiming = hasWordTiming
    }
}

public struct Lyrics: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case synced, plain, instrumental }

    public let kind: Kind
    /// Raw LRC for synced lyrics, plain text otherwise. Stored raw so the cache stays tiny and re-parses cheaply.
    public let source: String
    public let duration: TimeInterval?

    public init(kind: Kind, source: String, duration: TimeInterval?) {
        self.kind = kind
        self.source = source
        self.duration = duration
    }

    public var lines: [LyricLine] {
        switch kind {
        case .synced: LRCParser.parse(source, duration: duration)
        case .plain:
            source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, text in
                LyricLine(id: index, start: 0, end: 0, text: String(text), words: [], hasWordTiming: false)
            }
        case .instrumental: []
        }
    }
}
