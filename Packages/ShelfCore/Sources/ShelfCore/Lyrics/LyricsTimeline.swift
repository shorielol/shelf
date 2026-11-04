import Foundation

/// Answers "which line, and how far through each word" for a playback position.
public struct LyricsTimeline: Sendable, Equatable {
    public let lines: [LyricLine]

    public init(lines: [LyricLine]) {
        self.lines = lines
    }

    /// The last line whose start is at or before `time`. Binary search; called every frame.
    public func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    public func lineProgress(line index: Int, at time: TimeInterval) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let line = lines[index]
        return Self.fraction(time, from: line.start, to: line.end)
    }

    public func wordProgress(line index: Int, at time: TimeInterval) -> [Double] {
        guard lines.indices.contains(index) else { return [] }
        return lines[index].words.map { Self.fraction(time, from: $0.start, to: $0.end) }
    }

    static func fraction(_ time: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        guard end > start else { return time >= start ? 1 : 0 }
        return min(1, max(0, (time - start) / (end - start)))
    }
}
