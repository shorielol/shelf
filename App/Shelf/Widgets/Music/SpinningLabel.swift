import AppKit
import QuartzCore
import SwiftUI

/// The record label, turned by Core Animation. The render server does the spinning, so a playing turntable
/// costs the app nothing per frame. Pausing coasts it to a stop with constant deceleration.
struct SpinningLabel: NSViewRepresentable {
    let image: NSImage?
    let degreesPerSecond: Double
    let isSpinning: Bool

    func makeNSView(context: Context) -> LabelView { LabelView() }

    func updateNSView(_ view: LabelView, context: Context) {
        view.setImage(image)
        view.setSpinning(isSpinning, degreesPerSecond: degreesPerSecond)
    }

    final class LabelView: NSView {
        private let label = CALayer()
        private var spinning = false
        private var imageID: ObjectIdentifier?
        static let coastDuration: CFTimeInterval = 1.4
        private static let spinKey = "spin"

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            label.contentsGravity = .resizeAspectFill
            label.masksToBounds = true
            label.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
            layer?.addSublayer(label)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.bounds = bounds
            label.position = CGPoint(x: bounds.midX, y: bounds.midY)
            label.cornerRadius = min(bounds.width, bounds.height) / 2
            CATransaction.commit()
        }

        func setImage(_ image: NSImage?) {
            let id = image.map(ObjectIdentifier.init)
            guard id != imageID else { return }
            imageID = id
            label.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        func setSpinning(_ shouldSpin: Bool, degreesPerSecond: Double) {
            guard shouldSpin != spinning else { return }
            spinning = shouldSpin
            let current = (label.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
            label.removeAnimation(forKey: Self.spinKey)
            let omega = degreesPerSecond * .pi / 180  // radians per second; negative angles turn clockwise here
            if shouldSpin {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = current
                spin.toValue = current - 2 * .pi
                spin.duration = 2 * .pi / omega
                spin.repeatCount = .infinity
                label.add(spin, forKey: Self.spinKey)
            } else {
                // Constant deceleration from full speed covers half the distance full speed would.
                let end = current - CGFloat(omega * Self.coastDuration / 2)
                let coast = CABasicAnimation(keyPath: "transform.rotation.z")
                coast.fromValue = current
                coast.toValue = end
                coast.duration = Self.coastDuration
                coast.timingFunction = CAMediaTimingFunction(controlPoints: 1.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0, 1)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                label.setValue(end, forKeyPath: "transform.rotation.z")
                CATransaction.commit()
                label.add(coast, forKey: Self.spinKey)
            }
        }
    }
}
