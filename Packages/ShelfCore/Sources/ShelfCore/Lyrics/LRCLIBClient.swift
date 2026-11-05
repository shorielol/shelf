import Foundation
import os

/// One record from lrclib.net.
public struct LRCLIBRecord: Codable, Sendable, Equatable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?

    public init(id: Int, trackName: String, artistName: String, albumName: String?, duration: Double?, instrumental: Bool, plainLyrics: String?, syncedLyrics: String?) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    /// Nil when the record has no text and isn't marked instrumental, so a gap in the database isn't cached as "instrumental".
    public func lyrics(duration trackDuration: TimeInterval?) -> Lyrics? {
        if instrumental { return Lyrics(kind: .instrumental, source: "", duration: trackDuration) }
        if let synced = syncedLyrics, !synced.isEmpty { return Lyrics(kind: .synced, source: synced, duration: trackDuration) }
        if let plain = plainLyrics, !plain.isEmpty { return Lyrics(kind: .plain, source: plain, duration: trackDuration) }
        return nil
    }
}

/// Fetches lyrics from LRCLIB (free, no key). Exact match first, then search.
public struct LRCLIBClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    static let host = "lrclib.net"
    /// Search results within this many seconds of the playing track count as the same recording.
    static let durationTolerance: Double = 4

    private let userAgent: String
    private let transport: Transport
    private static let logger = Logger(subsystem: "app.shelf", category: "lyrics")

    public init(userAgent: String, transport: @escaping Transport = LRCLIBClient.urlSession) {
        self.userAgent = userAgent
        self.transport = transport
    }

    public static let urlSession: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public func lyrics(for track: Track) async -> Lyrics? {
        do {
            var exact: Lyrics?
            if let request = Self.getRequest(for: track, userAgent: userAgent) {
                let (data, status) = try await transport(request)
                if status == 200, let record = try? JSONDecoder().decode(LRCLIBRecord.self, from: data) {
                    exact = record.lyrics(duration: track.duration)
                }
            }
            // Synced and instrumental answers are final; plain-only ones are worth one search for a synced version.
            if let exact, exact.kind != .plain { return exact }
            guard let request = Self.searchRequest(for: track, userAgent: userAgent) else { return exact }
            let (data, status) = try await transport(request)
            guard status == 200, let records = try? JSONDecoder().decode([LRCLIBRecord].self, from: data) else { return exact }
            let found = Self.bestMatch(records, duration: track.duration)?.lyrics(duration: track.duration)
            return found?.kind == .synced ? found : (exact ?? found)
        } catch {
            Self.logger.error("Lyrics lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public static func getRequest(for track: Track, userAgent: String) -> URLRequest? {
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if let duration = track.duration { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded(.down))))) }
        return request(path: "/api/get", items: items, userAgent: userAgent)
    }

    static func searchRequest(for track: Track, userAgent: String) -> URLRequest? {
        request(path: "/api/search", items: [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ], userAgent: userAgent)
    }

    private static func request(path: String, items: [URLQueryItem], userAgent: String) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Synced lyrics from the closest-duration recording win; plain lyrics are the fallback.
    public static func bestMatch(_ records: [LRCLIBRecord], duration: TimeInterval?) -> LRCLIBRecord? {
        func distance(_ record: LRCLIBRecord) -> Double {
            guard let duration, let other = record.duration else { return 0 }
            return abs(other - duration)
        }
        let close = records.filter { distance($0) <= durationTolerance }
        let synced = close.filter { !($0.syncedLyrics ?? "").isEmpty }.min { distance($0) < distance($1) }
        return synced ?? close.filter { !($0.plainLyrics ?? "").isEmpty }.min { distance($0) < distance($1) }
    }
}
