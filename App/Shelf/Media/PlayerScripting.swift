import AppKit
import Foundation
import os
import ShelfCore

/// Runs AppleScript against Music and Spotify on one serial queue (NSAppleScript isn't thread-safe).
/// All scripts are fixed strings; the only interpolated values are numbers we produce ourselves.
nonisolated final class PlayerScripting: Sendable {
    static let shared = PlayerScripting()

    private let queue = DispatchQueue(label: "app.shelf.player-scripting", qos: .userInitiated)
    private static let logger = Logger(subsystem: "app.shelf", category: "player")

    enum Command: Sendable {
        case playPause, next, previous
        case seek(TimeInterval)
        case volume(Int)
    }

    func isRunning(_ source: PlayerSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier).isEmpty
    }

    func snapshot(of source: PlayerSource) async -> NowPlayingSnapshot? {
        guard isRunning(source) else { return nil }
        guard let raw = await run(Self.statusScript(for: source))?.stringValue else { return nil }
        return NowPlayingParser.parse(raw, source: source)
    }

    /// Music hands back artwork bytes; Spotify gives a URL instead (fetched by the caller).
    func musicArtwork() async -> Data? {
        guard isRunning(.music) else { return nil }
        let script = """
        tell application id "com.apple.Music"
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
        end tell
        """
        return await run(script)?.data
    }

    func volume(of source: PlayerSource) async -> Int? {
        guard isRunning(source) else { return nil }
        let value = await run("tell application id \"\(source.bundleIdentifier)\" to return sound volume")?.int32Value
        return value.map(Int.init)
    }

    func send(_ command: Command, to source: PlayerSource) async {
        guard isRunning(source) else { return }
        let target = "tell application id \"\(source.bundleIdentifier)\" to "
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let seconds): body = "set player position to \(String(format: "%.2f", max(0, seconds)))"
        case .volume(let level): body = "set sound volume to \(min(100, max(0, level)))"
        }
        _ = await run(target + body)
    }

    private static func statusScript(for source: PlayerSource) -> String {
        let artwork = source == .spotify ? "artwork url of t" : "\"\""
        let identifier = source == .spotify ? "id of t" : "persistent ID of t"
        return """
        tell application id "\(source.bundleIdentifier)"
            set s to player state as string
            if s is "stopped" then return "stopped"
            set t to current track
            set sep to character id 31
            return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & (\(identifier)) & sep & (\(artwork))
        end tell
        """
    }

    private func run(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    // -1743: not authorised; -600: app quit mid-call. Both are expected states, not bugs.
                    if code != -1743 && code != -600 {
                        Self.logger.error("AppleScript error \(code): \(String(describing: error[NSAppleScript.errorMessage]), privacy: .public)")
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }
}
