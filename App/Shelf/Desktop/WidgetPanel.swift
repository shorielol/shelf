import AppKit
import ShelfCore
import SwiftUI

extension NSScreen {
    var displayKey: DisplayKey { DisplayKey(name: localizedName, width: Int(frame.width), height: Int(frame.height)) }

    /// Converts a display-local, top-left-origin rect to global AppKit coordinates.
    func globalFrame(for rect: Rect) -> NSRect {
        NSRect(x: frame.minX + rect.x, y: frame.maxY - rect.y - rect.height, width: rect.width, height: rect.height)
    }

    /// Inverse of `globalFrame(for:)`.
    func localRect(for global: NSRect) -> Rect {
        Rect(x: global.minX - frame.minX, y: frame.maxY - global.maxY, width: global.width, height: global.height)
    }

    /// Usable area (below the menu bar, beside the Dock) in local coordinates.
    var localVisibleBounds: Rect { localRect(for: visibleFrame) }
}

/// Desktop-level window levels: widgets sit just above Finder's icons and below every app window.
enum DesktopLevel {
    static let widgets = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    static let editOverlay = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
    static let editingWidgets = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
}

/// One borderless, non-activating panel per widget. Transparent around the card so shadows aren't clipped
/// and clicks on the transparent margin fall through to the desktop.
final class WidgetPanel: NSPanel {
    /// Room around the card for its shadow and edit-mode chrome.
    static let inset: CGFloat = 18

    let widgetID: UUID

    init(widgetID: UUID, contentRect: NSRect, root: some View) {
        self.widgetID = widgetID
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = DesktopLevel.widgets
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        // Widgets spend most of the day under app windows. When a panel is fully covered, hide its
        // content so animations stop drawing; the window server still reports when it's uncovered.
        // SHELF_ALWAYS_DRAW=1 keeps drawing while covered, for capturing panels in tests.
        guard ProcessInfo.processInfo.environment["SHELF_ALWAYS_DRAW"] == nil else { return }
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.contentView?.isHidden = !self.occlusionState.contains(.visible)
            }
        }
    }

    private var occlusionObserver: NSObjectProtocol?

    /// Text widgets (sticky note, reminders) need key status to type.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
