import AppKit
import SwiftUI

/// Small motion helpers for the ambient widgets. Everything that moves is a pure function of time,
/// so a frozen clock (Reduce Motion) always lands on a good drawing.
nonisolated enum AmbientMotion {
    /// Smooth back-and-forth from -1 to 1. `t` and `period` in seconds, `phase` 0...1.
    static func wave(_ t: Double, period: Double, phase: Double = 0) -> Double {
        sin((t / period + phase) * .pi * 2)
    }

    /// Progress through a loop, 0...1.
    static func loop(_ t: Double, period: Double, phase: Double = 0) -> Double {
        let p = (t / period + phase).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    /// 0 at both ends, 1 in the middle. For things that fade in and out.
    static func bell(_ p: Double) -> Double {
        sin(.pi * min(1, max(0, p)))
    }

    /// Stable pseudo-random value in 0..<1 for item `i`.
    static func seeded(_ i: Int, salt: Double = 0) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// Strong ease-in-out, for things that travel.
    static func travel(_ p: Double) -> Double {
        let x = min(1, max(0, p))
        return x < 0.5 ? 16 * pow(x, 5) : 1 - pow(-2 * x + 2, 5) / 2
    }

    /// Strong ease-out, for things that open or arrive.
    static func arrive(_ p: Double) -> Double {
        let x = min(1, max(0, p))
        return 1 - pow(1 - x, 4)
    }

    /// A stable seed in 0..<1 from a widget id, so each instance gets its own tilt or palette offset.
    static func seed(from id: UUID) -> Double {
        let bytes = id.uuid
        return Double(Int(bytes.0) << 8 | Int(bytes.1)) / 65_536
    }
}

/// Exposes the hosting window so a widget can relate screen coordinates (the mouse) to itself.
struct HostWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowTrackingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}
