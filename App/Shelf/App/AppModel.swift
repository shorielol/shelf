import AppKit
import Observation
import os
import ShelfCore
import SwiftUI

/// App state: the layout, edit mode, and the shared services widgets read from.
@Observable
final class AppModel {
    private(set) var layout: WallLayout
    var isEditing = false {
        didSet { if !isEditing { showingGallery = false } }
    }
    var showingGallery = false
    var widgetsHidden = false
    var snapToGrid = true {
        didSet { UserDefaults.standard.set(snapToGrid, forKey: Keys.snap) }
    }
    var onboardingCompleted: Bool {
        didSet { UserDefaults.standard.set(onboardingCompleted, forKey: Keys.onboarding) }
    }

    let nowPlaying = NowPlayingService()
    let lyrics = LyricsService()
    let system = SystemStats()
    let weather = WeatherService()

    @ObservationIgnored private let store = JSONFileStore<WallLayout>(url: AppPaths.layout)
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private static let logger = Logger(subsystem: "app.shelf", category: "model")

    private enum Keys {
        static let snap = "snapToGrid"
        static let onboarding = "onboardingCompleted"
    }

    init() {
        let loaded = store.load()
        if loaded == nil { Self.quarantineUnreadableLayout(at: AppPaths.layout) }
        layout = loaded ?? WallLayout()
        onboardingCompleted = UserDefaults.standard.bool(forKey: Keys.onboarding)
        snapToGrid = UserDefaults.standard.object(forKey: Keys.snap) as? Bool ?? true
        nowPlaying.onTrackChange = { [weak self] track in
            guard let self else { return }
            lyrics.update(for: wantsLyrics ? track : nil)
        }
    }

    var snapper: GridSnapper { GridSnapper(step: snapToGrid ? 8 : 1, margin: 12) }

    func instance(_ id: UUID) -> WidgetInstance? {
        layout.widgets.first { $0.id == id }
    }

    // MARK: Mutations

    @discardableResult
    func add(kind: String, size: WidgetSize? = nil, on screen: NSScreen? = nil, at origin: CGPoint? = nil, config: WidgetConfig = [:]) -> UUID? {
        guard let descriptor = WidgetCatalog.descriptor(for: kind),
              let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let side = (size ?? descriptor.defaultSize).side
        let bounds = screen.localVisibleBounds
        let point = origin ?? freeSpot(for: CGSize(width: side.width, height: side.height), on: screen)
        let frame = snapper.snap(Rect(x: point.x, y: point.y, width: side.width, height: side.height), in: bounds)
        let instance = WidgetInstance(kind: kind, frame: frame, display: screen.displayKey,
                                      config: descriptor.defaultConfig.merging(config) { _, new in new })
        setLayout(layout.adding(instance))
        return instance.id
    }

    func remove(_ id: UUID) {
        setLayout(layout.removing(id: id))
    }

    func setFrame(_ id: UUID, _ frame: Rect, display: DisplayKey) {
        setLayout(layout.updating(id: id) {
            $0.frame = frame
            $0.display = display
        })
    }

    func resize(_ id: UUID, to size: WidgetSize) {
        guard let instance = instance(id),
              let screen = NSScreen.screens.first(where: { $0.displayKey == instance.display }) ?? NSScreen.main else { return }
        let side = size.side
        let frame = snapper.snap(Rect(x: instance.frame.x, y: instance.frame.y, width: side.width, height: side.height), in: screen.localVisibleBounds)
        setFrame(id, frame, display: instance.display)
    }

    func updateConfig(_ id: UUID, key: String, value: ConfigValue) {
        setLayout(layout.updating(id: id) { $0.config[key] = value })
    }

    func toggleLock(_ id: UUID) {
        setLayout(layout.updating(id: id) { $0.isLocked.toggle() })
    }

    func replaceAll(with widgets: [WidgetInstance]) {
        setLayout(WallLayout(widgets: widgets))
    }

    private func setLayout(_ next: WallLayout) {
        let hadLyrics = wantsLyrics
        layout = next
        if wantsLyrics != hadLyrics { lyrics.update(for: wantsLyrics ? nowPlaying.track : nil) }
        scheduleSave()
    }

    /// Lyrics are only looked up while a widget on the desktop shows them, so track names aren't sent anywhere otherwise.
    var wantsLyrics: Bool {
        layout.widgets.contains { widget in
            switch widget.kind {
            case "lyrics", "clickwheel": true
            case "turntable": widget.config.bool("lyrics", default: true) ?? true
            default: false
            }
        }
    }

    /// Writes any pending change immediately. Called on quit.
    func flush() {
        saveTask?.cancel()
        do {
            try store.save(layout)
        } catch {
            Self.logger.error("Saving layout on quit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A layout file that exists but won't decode is moved aside rather than overwritten by the next save.
    private static func quarantineUnreadableLayout(at url: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path), (try? Data(contentsOf: url)).map({ $0.count > 2 }) == true,
              JSONFileStore<WallLayout>(url: url).load() == nil else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = AppPaths.backups.appending(path: "layout-unreadable-\(stamp).json")
        try? manager.createDirectory(at: AppPaths.backups, withIntermediateDirectories: true)
        try? manager.moveItem(at: url, to: destination)
        logger.error("Layout file could not be read; moved it to \(destination.path, privacy: .public)")
    }

    /// Debounced so a drag doesn't write on every frame.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = layout
        saveTask = Task { [store] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try store.save(snapshot)
            } catch {
                Self.logger.error("Saving layout failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Scans the visible area in reading order for the first gap that fits.
    private func freeSpot(for size: CGSize, on screen: NSScreen) -> CGPoint {
        let bounds = screen.localVisibleBounds
        let key = screen.displayKey
        let occupied = layout.widgets.filter { $0.display == key }.map { CGRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height) }
        let step = 16.0, margin = 24.0
        var y = bounds.y + margin
        while y + size.height <= bounds.maxY - margin {
            var x = bounds.maxX - margin - size.width
            while x >= bounds.x + margin {
                let candidate = CGRect(x: x, y: y, width: size.width, height: size.height).insetBy(dx: -8, dy: -8)
                if !occupied.contains(where: { $0.intersects(candidate) }) { return CGPoint(x: x, y: y) }
                x -= step
            }
            y += step
        }
        return CGPoint(x: bounds.x + bounds.width / 2 - size.width / 2, y: bounds.y + bounds.height / 2 - size.height / 2)
    }
}
