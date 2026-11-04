import AppKit
import Observation
import ShelfCore
import SwiftUI

/// Keeps one `WidgetPanel` per widget in sync with the layout, plus the edit overlays.
final class DesktopHost {
    private let model: AppModel
    private var panels: [UUID: WidgetPanel] = [:]
    private var overlays: [EditOverlayWindow] = []
    private var screenObserver: NSObjectProtocol?
    private var dragStart: (mouse: NSPoint, frame: NSRect)?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        observe()
    }

    /// Re-runs whenever the layout, edit mode or visibility changes.
    private func observe() {
        withObservationTracking {
            _ = model.layout
            _ = model.isEditing
            _ = model.widgetsHidden
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcile()
                self?.observe()
            }
        }
        reconcile()
    }

    func reconcile() {
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else { return }
        let placed = model.layout.placement(connected: screens.map(\.displayKey), main: main.displayKey)
        let liveIDs = Set(placed.map(\.id))

        for (id, panel) in panels where !liveIDs.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        for instance in placed {
            guard let screen = screens.first(where: { $0.displayKey == instance.display }) ?? Optional(main) else { continue }
            let target = screen.globalFrame(for: instance.frame).insetBy(dx: -WidgetPanel.inset, dy: -WidgetPanel.inset)
            let panel = panels[instance.id] ?? makePanel(for: instance.id, frame: target)
            if dragStart == nil || panel.frame.size != target.size, panel.frame != target {
                panel.setFrame(target, display: true)
            }
            panel.level = model.isEditing ? DesktopLevel.editingWidgets : DesktopLevel.widgets
            if model.widgetsHidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
        syncOverlays(screens: screens)
    }

    private func makePanel(for id: UUID, frame: NSRect) -> WidgetPanel {
        let root = WidgetContainer(id: id, host: self).environment(model)
        let panel = WidgetPanel(widgetID: id, contentRect: frame, root: root)
        panels[id] = panel
        return panel
    }

    private func syncOverlays(screens: [NSScreen]) {
        guard model.isEditing else {
            overlays.forEach { $0.orderOut(nil) }
            overlays = []
            return
        }
        guard overlays.count != screens.count else { return }
        overlays.forEach { $0.orderOut(nil) }
        overlays = screens.map { screen in
            let window = EditOverlayWindow(screen: screen, root: EditOverlayView(isMain: screen == NSScreen.main).environment(model))
            window.orderFrontRegardless()
            return window
        }
    }

    // MARK: Dragging and resizing (driven by global mouse location so the moving window doesn't skew deltas)

    func beginInteraction(_ id: UUID) {
        guard let panel = panels[id] else { return }
        dragStart = (NSEvent.mouseLocation, panel.frame)
    }

    func drag(_ id: UUID) {
        guard let panel = panels[id], let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: start.frame.minX + mouse.x - start.mouse.x, y: start.frame.minY + mouse.y - start.mouse.y))
    }

    func resize(_ id: UUID, minimum: CGFloat = 120) {
        guard let panel = panels[id], let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        let width = max(minimum + WidgetPanel.inset * 2, start.frame.width + mouse.x - start.mouse.x)
        let height = max(minimum + WidgetPanel.inset * 2, start.frame.height - (mouse.y - start.mouse.y))
        panel.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
    }

    /// Snaps the panel's current frame onto the grid of whichever screen holds its centre, and saves it.
    func endInteraction(_ id: UUID) {
        defer { dragStart = nil }
        guard let panel = panels[id] else { return }
        let card = panel.frame.insetBy(dx: WidgetPanel.inset, dy: WidgetPanel.inset)
        let center = NSPoint(x: card.midX, y: card.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let snapped = model.snapper.snap(screen.localRect(for: card), in: screen.localVisibleBounds)
        let target = screen.globalFrame(for: snapped).insetBy(dx: -WidgetPanel.inset, dy: -WidgetPanel.inset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
        model.setFrame(id, snapped, display: screen.displayKey)
    }

    /// Launches a widget from a source rect (the onboarding window) to its place on the desktop.
    func flyIn(_ id: UUID, from source: NSRect, delay: TimeInterval) {
        guard let panel = panels[id] else { return }
        let target = panel.frame
        let start = NSRect(x: source.midX - target.width * 0.3, y: source.midY - target.height * 0.3,
                           width: target.width * 0.6, height: target.height * 0.6)
        panel.alphaValue = 0
        panel.setFrame(start, display: false)
        Task {
            try? await Task.sleep(for: .seconds(delay))
            Sounds.shared.play(.pop, volume: 0.4)
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.75
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Frame of a widget's card on screen, for the onboarding fly-in.
    func panelFrame(_ id: UUID) -> NSRect? {
        panels[id]?.frame.insetBy(dx: WidgetPanel.inset, dy: WidgetPanel.inset)
    }
}

/// Full-screen, translucent layer shown behind widgets in edit mode: grid dots and the toolbar.
final class EditOverlayWindow: NSPanel {
    init(screen: NSScreen, root: some View) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = DesktopLevel.editOverlay
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        contentView = NSHostingView(rootView: root)
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}
