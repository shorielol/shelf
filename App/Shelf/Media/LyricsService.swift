import Foundation
import Observation
import ShelfCore

/// Fetches and caches lyrics for the current track. Cache lives in Application Support, one small JSON per track.
@Observable
final class LyricsService {
    enum State: Equatable {
        case idle, loading, missing
        case loaded(Lyrics)
    }

    private(set) var state: State = .idle
    private(set) var timeline = LyricsTimeline(lines: [])
    /// Seconds added to playback time before lookup; positive shows lyrics earlier.
    var offset: TimeInterval {
        didSet { UserDefaults.standard.set(offset, forKey: Self.offsetKey) }
    }

    @ObservationIgnored private var currentID: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let client: LRCLIBClient
    @ObservationIgnored private let cacheDirectory: URL

    static let offsetKey = "lyricsOffset"

    init(cacheDirectory: URL = AppPaths.support.appending(path: "Lyrics", directoryHint: .isDirectory)) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        client = LRCLIBClient(userAgent: "Shelf/\(version) (https://github.com/shorielol/shelf)")
        self.cacheDirectory = cacheDirectory
        offset = UserDefaults.standard.double(forKey: Self.offsetKey)
    }

    func update(for track: Track?) {
        guard track?.id != currentID else { return }
        currentID = track?.id
        task?.cancel()
        guard let track else {
            set(.idle)
            return
        }
        let store = JSONFileStore<Lyrics>(url: cacheURL(for: track))
        if let cached = store.load() {
            set(.loaded(cached))
            return
        }
        set(.loading)
        task = Task { [client] in
            let lyrics = await client.lyrics(for: track)
            guard !Task.isCancelled, currentID == track.id else { return }
            if let lyrics {
                try? store.save(lyrics)
                set(.loaded(lyrics))
            } else {
                set(.missing)
            }
        }
    }

    /// Lyric lookup time for a playback position.
    func time(for position: TimeInterval) -> TimeInterval { position + offset }

    private func set(_ newState: State) {
        state = newState
        if case .loaded(let lyrics) = newState {
            timeline = LyricsTimeline(lines: lyrics.kind == .synced ? lyrics.lines : [])
        } else {
            timeline = LyricsTimeline(lines: [])
        }
    }

    private func cacheURL(for track: Track) -> URL {
        let safe = track.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return cacheDirectory.appending(path: "\(safe.prefix(120)).json")
    }
}
