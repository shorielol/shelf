import Foundation
import Testing
@testable import ShelfCore

@Suite struct LRCParserTests {
    @Test func `parses timestamped lines in order`() {
        let lrc = """
        [ar:Someone]
        [ti:A Song]
        [00:12.00]First line
        [00:15.50]Second line
        [00:20.25]Third line
        """
        let lines = LRCParser.parse(lrc)
        #expect(lines.map(\.text) == ["First line", "Second line", "Third line"])
        #expect(lines.map(\.start) == [12.0, 15.5, 20.25])
        #expect(lines.map(\.id) == [0, 1, 2])
    }

    @Test func `line end is the next line start, last line uses duration`() {
        let lines = LRCParser.parse("[00:01.00]a\n[00:03.00]b", duration: 10)
        #expect(lines[0].end == 3)
        #expect(lines[1].end == 10)
    }

    @Test func `last line without a duration gets a sensible end`() {
        let lines = LRCParser.parse("[00:01.00]a")
        #expect(lines[0].end > lines[0].start)
        #expect(lines[0].end <= lines[0].start + 6)
    }

    @Test func `repeated timestamps expand to several lines and sort`() {
        let lines = LRCParser.parse("[00:30.00][00:10.00]Chorus\n[00:20.00]Verse")
        #expect(lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
        #expect(lines.map(\.start) == [10, 20, 30])
    }

    @Test(arguments: [
        ("[01:02.5]x", 62.5),
        ("[01:02.50]x", 62.5),
        ("[01:02.500]x", 62.5),
        ("[1:02]x", 62.0),
        ("[10:00.00]x", 600.0),
    ])
    func `accepts timestamp variants`(input: String, expected: Double) {
        let lines = LRCParser.parse(input)
        #expect(lines.count == 1)
        #expect(abs(lines[0].start - expected) < 0.0001)
    }

    @Test func `offset tag shifts lines earlier when positive`() {
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]a")
        #expect(abs(lines[0].start - 9.5) < 0.0001)
    }

    @Test func `negative times clamp to zero`() {
        let lines = LRCParser.parse("[offset:+2000]\n[00:01.00]a")
        #expect(lines[0].start == 0)
    }

    @Test func `enhanced word tags give each word its own timing`() {
        let lines = LRCParser.parse("[00:10.00]<00:10.00>Hello <00:10.60>bright <00:11.20>world\n[00:13.00]next")
        let words = lines[0].words
        #expect(words.map(\.text) == ["Hello", "bright", "world"])
        #expect(words.map(\.start) == [10.0, 10.6, 11.2])
        #expect(words[0].end == 10.6)
        #expect(words[2].end <= 13.0)
        #expect(lines[0].text == "Hello bright world")
        #expect(lines[0].hasWordTiming)
    }

    @Test func `plain lines get interpolated word timing within the line`() {
        let lines = LRCParser.parse("[00:00.00]one two three\n[00:03.00]x")
        let words = lines[0].words
        #expect(words.count == 3)
        #expect(words[0].start == 0)
        #expect(words.last!.end <= 3.0)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.end <= $1.start + 0.0001 })
        #expect(!lines[0].hasWordTiming)
    }

    @Test func `long gaps do not stretch the karaoke wipe`() {
        let lines = LRCParser.parse("[00:00.00]hi\n[00:40.00]x")
        #expect(lines[0].words.last!.end < 5)
    }

    @Test func `empty timestamped lines are kept as breaks`() {
        let lines = LRCParser.parse("[00:01.00]a\n[00:02.00]\n[00:03.00]b")
        #expect(lines.count == 3)
        #expect(lines[1].isBreak)
    }

    @Test func `garbage input yields no lines`() {
        #expect(LRCParser.parse("no tags here\n[not a time]x").isEmpty)
    }

    @Test func `windows line endings are handled`() {
        let lines = LRCParser.parse("[00:01.00]a\r\n[00:02.00]b\r\n")
        #expect(lines.map(\.text) == ["a", "b"])
    }
}
