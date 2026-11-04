import Foundation
import Testing
@testable import ShelfCore

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct LyricsClientTests {
    let track = Track(id: "music:1", title: "Midnight City", artist: "M83", album: "Hurry Up, We're Dreaming", duration: 243.4)

    @Test func `builds the exact-match request with a polite user agent`() throws {
        let request = try #require(LRCLIBClient.getRequest(for: track, userAgent: "Shelf/1.0 (test)"))
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.host == "lrclib.net")
        #expect(components.path == "/api/get")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["track_name"] == "Midnight City")
        #expect(items["artist_name"] == "M83")
        #expect(items["album_name"] == "Hurry Up, We're Dreaming")
        #expect(items["duration"] == "243")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Shelf/1.0 (test)")
    }

    @Test func `exact match returns synced lyrics`() async throws {
        let data = try fixture("lrclib-get")
        let client = LRCLIBClient(userAgent: "t") { request in
            #expect(request.url?.path == "/api/get")
            return (data, 200)
        }
        let lyrics = try #require(await client.lyrics(for: track))
        #expect(lyrics.kind == .synced)
        #expect(lyrics.lines.first?.text == "Waiting in a car")
    }

    @Test func `falls back to search and picks the closest synced result`() async throws {
        let search = try fixture("lrclib-search")
        let client = LRCLIBClient(userAgent: "t") { request in
            if request.url?.path == "/api/get" { return (Data(), 404) }
            return (search, 200)
        }
        let lyrics = try #require(await client.lyrics(for: track))
        #expect(lyrics.kind == .synced)
        #expect(lyrics.lines.first?.text == "Waiting in a car")
    }

    @Test func `best match prefers synced within tolerance then plain`() throws {
        let records = try JSONDecoder().decode([LRCLIBRecord].self, from: try fixture("lrclib-search"))
        #expect(LRCLIBClient.bestMatch(records, duration: 243.4)?.id == 3)
        #expect(LRCLIBClient.bestMatch(records.filter { $0.id != 3 }, duration: 243.4)?.id == 2)
        #expect(LRCLIBClient.bestMatch([], duration: 100) == nil)
    }

    @Test func `instrumental records map to the instrumental kind`() throws {
        let record = LRCLIBRecord(id: 9, trackName: "x", artistName: "y", albumName: nil, duration: 100, instrumental: true, plainLyrics: nil, syncedLyrics: nil)
        #expect(record.lyrics(duration: 100).kind == .instrumental)
    }

    @Test func `network failure returns nil instead of throwing`() async {
        struct Boom: Error {}
        let client = LRCLIBClient(userAgent: "t") { _ in throw Boom() }
        #expect(await client.lyrics(for: track) == nil)
    }
}
