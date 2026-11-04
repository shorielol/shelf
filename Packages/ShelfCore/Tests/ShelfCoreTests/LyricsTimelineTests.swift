import Foundation
import Testing
@testable import ShelfCore

@Suite struct LyricsTimelineTests {
    let timeline = LyricsTimeline(lines: LRCParser.parse("[00:05.00]a b\n[00:10.00]c\n[00:20.00]d", duration: 30))

    @Test func `no line is active before the first timestamp`() {
        #expect(timeline.lineIndex(at: 4.99) == nil)
    }

    @Test(arguments: [(5.0, 0), (9.99, 0), (10.0, 1), (19.0, 1), (25.0, 2), (999.0, 2)])
    func `finds the active line`(time: Double, index: Int) {
        #expect(timeline.lineIndex(at: time) == index)
    }

    @Test func `word progress runs from zero to one`() {
        let line = timeline.lines[0]
        #expect(timeline.wordProgress(line: 0, at: 4) == [0, 0])
        let mid = timeline.wordProgress(line: 0, at: line.words[0].start + (line.words[0].end - line.words[0].start) / 2)
        #expect(mid[0] > 0.4 && mid[0] < 0.6)
        #expect(mid[1] == 0)
        #expect(timeline.wordProgress(line: 0, at: 9.9) == [1, 1])
    }

    @Test func `line progress is clamped`() {
        #expect(timeline.lineProgress(line: 1, at: 0) == 0)
        #expect(timeline.lineProgress(line: 1, at: 15) == 0.5)
        #expect(timeline.lineProgress(line: 1, at: 100) == 1)
    }

    @Test func `empty timeline is safe`() {
        let empty = LyricsTimeline(lines: [])
        #expect(empty.lineIndex(at: 10) == nil)
        #expect(empty.wordProgress(line: 3, at: 1).isEmpty)
    }
}
