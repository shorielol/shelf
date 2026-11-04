import Foundation
import Testing
@testable import ShelfCore

@Suite struct NowPlayingParserTests {
    let sep = NowPlayingParser.separator

    @Test func `parses a playing snapshot`() throws {
        let raw = ["playing", "Midnight City", "M83", "Hurry Up, We're Dreaming", "243.5", "61.25", "ABC123", "https://i.scdn.co/image/x"].joined(separator: sep)
        let snapshot = try #require(NowPlayingParser.parse(raw, source: .spotify))
        #expect(snapshot.isPlaying)
        #expect(snapshot.track.title == "Midnight City")
        #expect(snapshot.track.artist == "M83")
        #expect(snapshot.track.album == "Hurry Up, We're Dreaming")
        #expect(snapshot.track.duration == 243.5)
        #expect(snapshot.position == 61.25)
        #expect(snapshot.track.id == "spotify:ABC123")
        #expect(snapshot.artworkURL == URL(string: "https://i.scdn.co/image/x"))
    }

    @Test func `spotify reports duration in milliseconds`() throws {
        let raw = ["paused", "T", "A", "B", "243500", "10", "id", ""].joined(separator: sep)
        let snapshot = try #require(NowPlayingParser.parse(raw, source: .spotify))
        #expect(snapshot.track.duration == 243.5)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.artworkURL == nil)
    }

    @Test func `locale decimal commas are accepted`() throws {
        let raw = ["playing", "T", "A", "B", "200,5", "3,25", "id", ""].joined(separator: sep)
        let snapshot = try #require(NowPlayingParser.parse(raw, source: .music))
        #expect(snapshot.track.duration == 200.5)
        #expect(snapshot.position == 3.25)
    }

    @Test(arguments: ["", "stopped", "notrunning", "playing\u{1F}only"])
    func `stopped or malformed output is nil`(raw: String) {
        #expect(NowPlayingParser.parse(raw, source: .music) == nil)
    }

    @Test func `missing id falls back to a stable hash of the metadata`() throws {
        let raw = ["playing", "T", "A", "B", "100", "1", "", ""].joined(separator: sep)
        let a = try #require(NowPlayingParser.parse(raw, source: .music))
        let b = try #require(NowPlayingParser.parse(raw, source: .music))
        #expect(a.track.id == b.track.id)
        #expect(!a.track.id.isEmpty)
    }
}
