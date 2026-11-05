import Foundation
import Testing
@testable import ShelfCore

/// Regressions found in code review.
@Suite struct ReviewRegressionTests {
    func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func `evening in New York still gives that day's sunset`() throws {
        // 22:00 EDT on 21 June is 02:00 UTC on 22 June.
        let times = try #require(SunTimes(date: utc(2024, 6, 22, 2), latitude: 40.71, longitude: -74.01))
        // Almanac: sunset 20:31 EDT = 00:31 UTC on 22 June.
        #expect(abs(times.sunset.timeIntervalSince(utc(2024, 6, 22, 0, 31))) < 300)
    }

    @Test func `early morning in Tokyo gives that day's sunrise`() throws {
        // 05:00 JST on 21 June is 20:00 UTC on 20 June.
        let times = try #require(SunTimes(date: utc(2024, 6, 20, 20), latitude: 35.68, longitude: 139.69))
        // Almanac: sunrise 04:25 JST = 19:25 UTC on 20 June.
        #expect(abs(times.sunrise.timeIntervalSince(utc(2024, 6, 20, 19, 25))) < 300)
    }

    @Test func `short spotify tracks are still read as milliseconds`() throws {
        let raw = ["playing", "Skit", "A", "B", "30000", "1", "id", ""].joined(separator: NowPlayingParser.separator)
        let snapshot = try #require(NowPlayingParser.parse(raw, source: .spotify))
        #expect(snapshot.track.duration == 30)
    }

    @Test func `music durations are seconds even when long`() throws {
        let raw = ["playing", "Mix", "A", "B", "40000", "1", "id", ""].joined(separator: NowPlayingParser.separator)
        let snapshot = try #require(NowPlayingParser.parse(raw, source: .music))
        #expect(snapshot.track.duration == 40000)
    }

    @Test func `snapping keeps preset sizes exact`() {
        let snapper = GridSnapper(step: 8, margin: 16)
        let bounds = Rect(x: 0, y: 0, width: 1600, height: 1000)
        for preset in WidgetSize.allCases {
            let snapped = snapper.snap(Rect(x: 101, y: 99, width: preset.side.width, height: preset.side.height), in: bounds)
            #expect(snapped.width == preset.side.width && snapped.height == preset.side.height)
        }
    }
}

@Suite struct LyricsCachePolicyTests {
    let track = Track(id: "music:1", title: "Midnight City", artist: "M83", album: "Hurry Up", duration: 243.4)

    @Test func `a record with no lyrics text is not treated as instrumental`() {
        let record = LRCLIBRecord(id: 1, trackName: "x", artistName: "y", albumName: nil, duration: 100, instrumental: false, plainLyrics: nil, syncedLyrics: "")
        #expect(record.lyrics(duration: 100) == nil)
    }

    @Test func `a plain-only exact match still looks for synced lyrics`() async throws {
        let plainOnly = try JSONEncoder().encode(LRCLIBRecord(id: 5, trackName: "Midnight City", artistName: "M83", albumName: "Hurry Up", duration: 243, instrumental: false, plainLyrics: "plain", syncedLyrics: nil))
        let search = try JSONEncoder().encode([LRCLIBRecord(id: 6, trackName: "Midnight City", artistName: "M83", albumName: "Hurry Up", duration: 243, instrumental: false, plainLyrics: "p", syncedLyrics: "[00:01.00]synced")])
        let client = LRCLIBClient(userAgent: "t") { request in
            request.url?.path == "/api/get" ? (plainOnly, 200) : (search, 200)
        }
        let lyrics = try #require(await client.lyrics(for: track))
        #expect(lyrics.kind == .synced)
    }

    @Test func `plain lyrics are kept when search has nothing better`() async throws {
        let plainOnly = try JSONEncoder().encode(LRCLIBRecord(id: 5, trackName: "Midnight City", artistName: "M83", albumName: "Hurry Up", duration: 243, instrumental: false, plainLyrics: "plain", syncedLyrics: nil))
        let client = LRCLIBClient(userAgent: "t") { request in
            request.url?.path == "/api/get" ? (plainOnly, 200) : (Data("[]".utf8), 200)
        }
        let lyrics = try #require(await client.lyrics(for: track))
        #expect(lyrics.kind == .plain)
    }
}
