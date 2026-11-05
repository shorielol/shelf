import SwiftUI

/// A one-shot handful of paper confetti, thrown up from the bottom and left to fall.
/// Every particle's path is a closed-form function of time, so there is no per-frame state.
struct ConfettiBurst: View {
    let start: Date
    static let duration: TimeInterval = 2.6

    private static let colors: [Color] = [Theme.ember, Theme.brass, Theme.cream, Theme.moss]
    private static let count = 38

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t >= 0, t < Self.duration else { return }
                for index in 0..<Self.count { draw(index, t: t, in: &context, size: size) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ index: Int, t: Double, in context: inout GraphicsContext, size: CGSize) {
        let seed = Double(index)
        let spread = noise(seed * 1.7) * 2 - 1
        let speed = size.height * (1.0 + noise(seed * 3.1) * 0.55)
        let angle = (-90 + spread * 38) * .pi / 180
        let gravity = size.height * 2.6
        let drag = exp(-t * 1.4)
        let x = size.width * 0.5 + cos(angle) * speed * (1 - drag) / 1.4 + sin(t * 6 + seed) * 4
        let y = size.height * 0.95 + sin(angle) * speed * (1 - drag) / 1.4 + 0.5 * gravity * t * t * 0.35
        let fade = min(1, (Self.duration - t) / 0.6)
        var piece = context
        piece.opacity = fade
        piece.translateBy(x: x, y: y)
        piece.rotate(by: .radians(t * (4 + noise(seed * 5.3) * 6) + seed))
        // A flat strip that tumbles: its width oscillates as it turns over.
        let width = 7 * abs(cos(t * 9 + seed))
        piece.fill(Path(CGRect(x: -width / 2, y: -2, width: max(1, width), height: 4)),
                   with: .color(Self.colors[index % Self.colors.count]))
    }

    /// Deterministic 0...1 hash.
    private func noise(_ value: Double) -> Double {
        let raw = sin(value * 12.9898) * 43_758.5453
        return raw - raw.rounded(.down)
    }
}
