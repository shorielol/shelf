import AppKit
import Foundation
import Observation
import ShelfCore

/// Single source of truth for what's playing. Widgets read it; nothing polls when no player is running.
@Observable
final class NowPlayingService {
    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var clock: PlaybackClock = .stopped
    private(set) var artwork: NSImage?
    private(set) var palette: ArtworkPalette = .fallback
    private(set) var volume: Int = 50
    private(set) var isAuthorized = true

    var track: Track? { snapshot?.track }
    var source: PlayerSource? { snapshot?.source }
    var isPlaying: Bool { clock.isPlaying }

    /// Called when the playing track changes (or stops), so lyrics can follow.
    @ObservationIgnored var onTrackChange: ((Track?) -> Void)?

    @ObservationIgnored private let scripting = PlayerScripting.shared
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var artworkTrackID: String?
    @ObservationIgnored private var preferred: PlayerSource?

    static let playingInterval: Duration = .seconds(1)
    static let idleInterval: Duration = .seconds(4)

    func start() {
        guard pollTask == nil else { return }
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let source: PlayerSource = note.name.rawValue.hasPrefix("com.spotify") ? .spotify : .music
                MainActor.assumeIsolated {
                    self?.preferred = source
                    self?.refreshNow()
                }
            })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.isPlaying ? Self.playingInterval : Self.idleInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
    }

    func refreshNow() {
        Task { await refresh() }
    }

    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var artworkAttempts = 0
    static let maxArtworkAttempts = 3

    // MARK: Controls (optimistic, then confirmed by the next refresh)

    func playPause() {
        guard let source else { return }
        let now = Date()
        clock = PlaybackClock(position: clock.position(at: now), anchor: now, isPlaying: !clock.isPlaying, duration: clock.duration)
        send(.playPause, to: source)
    }

    func next() { if let source { send(.next, to: source) } }
    func previous() { if let source { send(.previous, to: source) } }

    func seek(to seconds: TimeInterval) {
        guard let source else { return }
        clock = PlaybackClock(position: seconds, anchor: Date(), isPlaying: clock.isPlaying, duration: clock.duration)
        send(.seek(seconds), to: source)
    }

    /// The wheel can fire many detents a second; only the latest level is sent, 80 ms after the last change.
    func setVolume(_ level: Int) {
        guard let source else { return }
        volume = min(100, max(0, level))
        volumeTask?.cancel()
        volumeTask = Task { [volume, scripting] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await scripting.send(.volume(volume), to: source)
        }
    }

    private func send(_ command: PlayerScripting.Command, to source: PlayerSource) {
        Task {
            await scripting.send(command, to: source)
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        }
    }

    // MARK: Refresh

    /// Overlapping refreshes collapse into one follow-up, so rapid controls can't pile scripts up on the queue.
    private func refresh() async {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            await refreshOnce()
        } while refreshQueued
    }

    private func refreshOnce() async {
        let order: [PlayerSource] = preferred == .spotify ? [.spotify, .music] : [.music, .spotify]
        var chosen: NowPlayingSnapshot?
        for candidate in order {
            guard let snapshot = await scripting.snapshot(of: candidate) else { continue }
            if snapshot.isPlaying { chosen = snapshot; break }
            if chosen == nil { chosen = snapshot }
        }
        apply(chosen)
    }

    private func apply(_ next: NowPlayingSnapshot?) {
        let now = Date()
        guard let next else {
            if snapshot != nil {
                snapshot = nil
                clock = .stopped
                artwork = nil
                palette = .fallback
                artworkTrackID = nil
                onTrackChange?(nil)
            }
            return
        }
        let trackChanged = next.track != snapshot?.track
        if snapshot != next { snapshot = next }
        if trackChanged { onTrackChange?(next.track) }
        clock = trackChanged
            ? PlaybackClock(position: next.position, anchor: now, isPlaying: next.isPlaying, duration: next.track.duration)
            : clock.reconciled(reported: next.position, at: now, isPlaying: next.isPlaying, duration: next.track.duration)
        let artworkMissing = artwork == nil && artworkAttempts < Self.maxArtworkAttempts
        if artworkTrackID != next.track.id || artworkMissing {
            if artworkTrackID != next.track.id { artworkAttempts = 0 }
            artworkTrackID = next.track.id
            artworkAttempts += 1
            Task { await loadArtwork(for: next) }
            Task { if let level = await scripting.volume(of: next.source) { volume = level } }
        }
    }

    private func loadArtwork(for snapshot: NowPlayingSnapshot) async {
        let data: Data?
        switch snapshot.source {
        case .music: data = await scripting.musicArtwork()
        case .spotify:
            if let url = snapshot.artworkURL, url.scheme == "https" {
                data = try? await URLSession.shared.data(from: url).0
            } else {
                data = nil
            }
        }
        guard artworkTrackID == snapshot.track.id else { return }  // track changed while loading
        let image = data.flatMap(NSImage.init(data:))
        artwork = image
        if let image {
            palette = await ArtworkPalette.extract(from: image)
        } else {
            palette = .fallback
        }
    }
}
