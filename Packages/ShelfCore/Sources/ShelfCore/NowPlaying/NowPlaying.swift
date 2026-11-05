import Foundation

public enum PlayerSource: String, Codable, Sendable, CaseIterable {
    case music, spotify

    public var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    public var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

public struct Track: Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval?

    public init(id: String, title: String, artist: String, album: String, duration: TimeInterval?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

/// One reading from a player.
public struct NowPlayingSnapshot: Sendable, Equatable {
    public let source: PlayerSource
    public let track: Track
    public let isPlaying: Bool
    public let position: TimeInterval
    public let artworkURL: URL?

    public init(source: PlayerSource, track: Track, isPlaying: Bool, position: TimeInterval, artworkURL: URL?) {
        self.source = source
        self.track = track
        self.isPlaying = isPlaying
        self.position = position
        self.artworkURL = artworkURL
    }
}

/// Parses the separator-joined output of the player AppleScripts:
/// state, title, artist, album, duration, position, id, artwork URL.
public enum NowPlayingParser {
    public static let separator = "\u{1F}"
    public static func parse(_ raw: String, source: PlayerSource) -> NowPlayingSnapshot? {
        let fields = raw.components(separatedBy: separator)
        guard fields.count >= 8 else { return nil }
        let state = fields[0].lowercased()
        guard state == "playing" || state == "paused" else { return nil }
        let title = fields[1], artist = fields[2], album = fields[3]
        guard !title.isEmpty else { return nil }

        var duration = number(fields[4])
        // Spotify reports duration in milliseconds, Music in seconds.
        if source == .spotify, let value = duration { duration = value / 1000 }
        let position = max(0, number(fields[5]) ?? 0)
        let rawID = fields[6].trimmingCharacters(in: .whitespaces)
        let id = rawID.isEmpty ? stableID(title: title, artist: artist, album: album) : rawID
        let artwork = fields[7].isEmpty ? nil : URL(string: fields[7])

        let track = Track(id: "\(source.rawValue):\(id)", title: title, artist: artist, album: album, duration: duration)
        return NowPlayingSnapshot(source: source, track: track, isPlaying: state == "playing", position: position, artworkURL: artwork)
    }

    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// FNV-1a; `hashValue` is seeded per launch, so it can't key a disk cache.
    static func stableID(title: String, artist: String, album: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(title)|\(artist)|\(album)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
