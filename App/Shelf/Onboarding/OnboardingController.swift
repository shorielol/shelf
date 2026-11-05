import AppKit
import ShelfCore
import SwiftUI

/// Owns the welcome window and the hand-off where chosen widgets fly out of it onto the desktop.
final class OnboardingController {
    private let model: AppModel
    private let host: DesktopHost
    private let onClose: () -> Void
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    init(model: AppModel, host: DesktopHost, onClose: @escaping () -> Void) {
        self.model = model
        self.host = host
        self.onClose = onClose
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.graphite)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: OnboardingView(finish: { [weak self] layout in self?.finish(with: layout) }).environment(model))
        window.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closed() }
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func focus() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(with layout: StarterLayout?) {
        model.onboardingCompleted = true
        guard let window else { return }
        guard let layout, let screen = window.screen ?? NSScreen.main else {
            window.close()
            return
        }
        let ids = layout.apply(to: model, on: screen)
        host.reconcile()
        let origin = window.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { window.close() }
        }
        for (index, id) in ids.enumerated() {
            host.flyIn(id, from: origin, delay: 0.08 + Double(index) * 0.09)
        }
    }

    private func closed() {
        model.onboardingCompleted = true
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
        onClose()
    }
}

/// Starter arrangements offered at the end of onboarding, anchored to the top-right of the screen.
enum StarterLayout: String, CaseIterable, Identifiable {
    case listening, focus, minimal
    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: "Listening Room"
        case .focus: "Focus Desk"
        case .minimal: "Minimal"
        }
    }

    var summary: String {
        switch self {
        case .listening: "Turntable, click wheel and synced lyrics."
        case .focus: "Flip clock, focus timer, calendar and weather."
        case .minimal: "A clock, the weather and what's playing."
        }
    }

    /// Columns of (kind, size), laid out right to left, top to bottom.
    var columns: [[(String, WidgetSize)]] {
        switch self {
        case .listening: [[("turntable", .large), ("nowplaying", .medium)], [("lyrics", .large), ("cassette", .medium)], [("clickwheel", .large)]]
        case .focus: [[("flipclock", .medium), ("calendar", .large)], [("focustimer", .small), ("weather", .small), ("dayprogress", .small)]]
        case .minimal: [[("analogclock", .small), ("weather", .small), ("nowplaying", .small)]]
        }
    }

    var symbols: [String] {
        columns.flatMap { $0 }.compactMap { WidgetCatalog.descriptor(for: $0.0)?.symbol }
    }

    @discardableResult
    func apply(to model: AppModel, on screen: NSScreen) -> [UUID] {
        let bounds = screen.localVisibleBounds
        let gap = 16.0, margin = 32.0
        var ids: [UUID] = []
        var right = bounds.maxX - margin
        for column in columns {
            let available = column.filter { WidgetCatalog.descriptor(for: $0.0) != nil }
            let width = available.map { $0.1.side.width }.max() ?? 0
            var y = bounds.y + margin
            for (kind, size) in available {
                let side = size.side
                guard y + side.height <= bounds.maxY - margin else { break }
                if let id = model.add(kind: kind, size: size, on: screen, at: CGPoint(x: right - side.width, y: y)) { ids.append(id) }
                y += side.height + gap
            }
            right -= width + gap
        }
        return ids
    }
}
