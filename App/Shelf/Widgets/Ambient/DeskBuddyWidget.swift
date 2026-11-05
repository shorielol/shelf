import AppKit
import ShelfCore
import SwiftUI

/// A small round creature with a sprout on its head. It breathes, blinks, follows the cursor with its eyes,
/// bobs along when music plays and gets sleepy after ten at night. Tap it and it hops.
struct DeskBuddyWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var brain = BuddyBrain()

    enum Coat: String, CaseIterable {
        case cream, clay, sage, slate
        var label: String { rawValue.capitalized }
        var colors: BuddyColors {
            switch self {
            case .cream: BuddyColors(body: Theme.cream, shade: Color(red: 0.85, green: 0.80, blue: 0.72), sprout: Theme.moss)
            case .clay: BuddyColors(body: Color(red: 0.86, green: 0.52, blue: 0.40), shade: Color(red: 0.70, green: 0.38, blue: 0.29), sprout: Theme.moss)
            case .sage: BuddyColors(body: Color(red: 0.70, green: 0.79, blue: 0.64), shade: Color(red: 0.53, green: 0.63, blue: 0.48), sprout: Theme.brass)
            case .slate: BuddyColors(body: Color(red: 0.58, green: 0.62, blue: 0.68), shade: Color(red: 0.43, green: 0.47, blue: 0.53), sprout: Theme.brass)
            }
        }
    }

    private var coat: Coat { Coat(rawValue: context.string("coat", "cream")) ?? .cream }

    var body: some View {
        let asleep = BuddyBrain.isNight(Date())
        TimelineView(.animation(minimumInterval: asleep ? 1.0 / 12.0 : 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let pose = brain.pose(at: timeline.date, music: model.nowPlaying.isPlaying, still: reduceMotion)
            let colors = coat.colors
            Canvas { canvas, size in
                BuddyArt.draw(pose, colors: colors, in: &canvas, size: size)
            }
        }
        .background(HostWindowReader { brain.window = $0 }.frame(width: 0, height: 0))
        .frame(width: context.size.width, height: context.size.height)
        .contentShape(.rect)
        .onTapGesture {
            guard !reduceMotion else { return }
            brain.hop()
            Sounds.shared.play(.pop, volume: 0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desk buddy")
        .accessibilityValue(asleep ? "Sleepy" : (model.nowPlaying.isPlaying ? "Bobbing to the music" : "Awake, watching the cursor"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Makes it hop")
    }
}

nonisolated struct BuddyColors: Sendable {
    let body: Color
    let shade: Color
    let sprout: Color
}

/// Everything the drawing needs for one frame. Units are a 100 x 100 box.
nonisolated struct BuddyPose: Sendable {
    var t: Double = 0
    var lift: Double = 0
    var squashY: Double = 1
    var lean: Double = 0
    var sprout: Double = 0
    var gazeX: Double = 0
    var gazeY: Double = 0
    var lid: Double = 0
    var squint: Double = 0
    var asleep = false
}

/// Turns time, the cursor and the music state into a pose. Holds the little bit of memory
/// motion needs (where the eyes are now, when the next blink is) so nothing ever jumps.
final class BuddyBrain {
    weak var window: NSWindow?

    private let start = Date()
    private var lastFrame = Date()
    private var gaze = CGPoint.zero
    private var target = CGPoint.zero
    private var lastPoll = Date.distantPast
    private var lastMouse = CGPoint.zero
    private var lastMouseMove = Date.distantPast
    private var nextGlance = Date()
    private var nextBlink = Date().addingTimeInterval(2)
    private var blinks: [Date] = []
    private var hopStart: Date?
    private var music = 0.0
    private var restLid = 0.0

    private static let pollInterval: TimeInterval = 0.12
    private static let hopLength: TimeInterval = 0.62

    static func isNight(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 6
    }

    func hop() {
        if let hopStart, Date().timeIntervalSince(hopStart) < Self.hopLength { return }
        hopStart = Date()
        blinks.append(Date().addingTimeInterval(0.05))
    }

    func pose(at date: Date, music isPlaying: Bool, still: Bool) -> BuddyPose {
        let night = Self.isNight(date)
        guard !still else { return BuddyPose(lid: night ? 0.55 : 0, asleep: night) }
        let dt = min(0.2, max(0, date.timeIntervalSince(lastFrame)))
        lastFrame = date
        let t = date.timeIntervalSince(start)

        updateGazeTarget(at: date, night: night)
        let follow = 1 - exp(-dt / 0.16)
        gaze.x += (target.x - gaze.x) * follow
        gaze.y += (target.y - gaze.y) * follow
        music += ((isPlaying ? 1 : 0) - music) * (1 - exp(-dt / 0.6))
        restLid += ((night ? 0.55 : 0) - restLid) * (1 - exp(-dt / 1.5))

        var pose = BuddyPose(t: t, gazeX: gaze.x, gazeY: gaze.y, asleep: night)
        applyBody(&pose, t: t, night: night)
        applyHop(&pose, at: date)
        pose.lid = max(restLid, blinkLid(at: date, night: night))
        return pose
    }

    // MARK: Body

    private func lean(_ t: Double) -> Double {
        2.5 * music * AmbientMotion.wave(t, period: 1.1) + 1.2 * AmbientMotion.wave(t, period: 7.3)
    }

    private func applyBody(_ pose: inout BuddyPose, t: Double, night: Bool) {
        let breathPeriod = night ? 5.5 : 3.8
        let breath = AmbientMotion.wave(t, period: breathPeriod)
        let bob = music * 2.2 * (1 - cos(2 * .pi * t / 0.55)) / 2
        pose.squashY = 1 + 0.014 * breath - music * 0.025 * (1 - cos(2 * .pi * t / 0.55)) / 2
        pose.lift = bob + 0.6 * (breath + 1) / 2
        pose.lean = lean(t)
        // The sprout trails the body: its own sway plus a delayed, opposite copy of the lean.
        pose.sprout = 4 * AmbientMotion.wave(t - 0.15, period: breathPeriod * 1.3) - 0.6 * lean(t - 0.12) * 2
    }

    private func applyHop(_ pose: inout BuddyPose, at date: Date) {
        guard let hopStart else { return }
        let e = date.timeIntervalSince(hopStart)
        guard e < Self.hopLength + 0.9 else { self.hopStart = nil; return }
        pose.squint = AmbientMotion.bell(min(1, e / (Self.hopLength + 0.9)))
        switch e {
        case ..<0.1:
            pose.squashY *= 1 - 0.07 * AmbientMotion.travel(e / 0.1)
        case ..<0.44:
            let s = (e - 0.1) / 0.34
            pose.lift += 12 * (1 - pow(2 * s - 1, 2))
            pose.squashY *= 1 + 0.06 * sin(.pi * s)
        case ..<Self.hopLength:
            let s = (e - 0.44) / (Self.hopLength - 0.44)
            pose.squashY *= 1 - 0.12 * sin(.pi * s) * (1 - s * 0.4)
        default:
            break
        }
    }

    // MARK: Eyes

    private func updateGazeTarget(at date: Date, night: Bool) {
        if date.timeIntervalSince(lastPoll) >= Self.pollInterval {
            lastPoll = date
            let mouse = NSEvent.mouseLocation
            if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 2 { lastMouseMove = date }
            lastMouse = mouse
        }
        let previous = target
        if date.timeIntervalSince(lastMouseMove) < 5, let frame = window?.frame {
            let dx = lastMouse.x - frame.midX, dy = lastMouse.y - frame.midY
            let distance = max(1, hypot(dx, dy))
            let reach = min(1, distance / 260)
            target = CGPoint(x: dx / distance * reach, y: -dy / distance * reach)
        } else if date >= nextGlance {
            // Nothing to watch: idle glances, held for a few seconds each.
            let seed = Int(date.timeIntervalSince(start))
            target = CGPoint(x: (AmbientMotion.seeded(seed, salt: 1) - 0.5) * 1.2,
                             y: night ? 0.45 : (AmbientMotion.seeded(seed, salt: 2) - 0.5) * 0.6)
            nextGlance = date.addingTimeInterval(2.5 + AmbientMotion.seeded(seed, salt: 3) * 3)
        }
        // A big change of view comes with a blink, as it does for people.
        if hypot(target.x - previous.x, target.y - previous.y) > 0.8, (blinks.last.map { date.timeIntervalSince($0) > 1 } ?? true) {
            blinks.append(date)
        }
    }

    private func blinkLid(at date: Date, night: Bool) -> Double {
        if date >= nextBlink {
            blinks.append(date)
            if Double.random(in: 0..<1) < 0.15 { blinks.append(date.addingTimeInterval(0.42)) }
            nextBlink = date.addingTimeInterval(night ? .random(in: 5...9) : .random(in: 2.6...5.2))
        }
        blinks.removeAll { date.timeIntervalSince($0) > 0.6 }
        let close = night ? 0.18 : 0.11, hold = 0.04, open = night ? 0.3 : 0.19
        var lid = 0.0
        for blink in blinks {
            let e = date.timeIntervalSince(blink)
            guard e >= 0 else { continue }
            let value: Double = switch e {
            case ..<close: AmbientMotion.travel(e / close)
            case ..<(close + hold): 1
            case ..<(close + hold + open): 1 - AmbientMotion.arrive((e - close - hold) / open)
            default: 0
            }
            lid = max(lid, value)
        }
        return lid
    }
}

/// The drawing. A pebble body squashing from its feet, a face that slides a little toward the gaze,
/// eyes with lids, cheeks, a sprout on a pivot, and a shadow that shrinks as the body rises.
nonisolated enum BuddyArt {
    private static let ink = Color(red: 0.16, green: 0.14, blue: 0.13)
    private static let blush = Color(red: 0.93, green: 0.45, blue: 0.40)

    static func draw(_ pose: BuddyPose, colors: BuddyColors, in canvas: inout GraphicsContext, size: CGSize) {
        let unit = min(size.width, size.height) / 100
        canvas.translateBy(x: (size.width - unit * 100) / 2, y: (size.height - unit * 100) / 2)
        canvas.scaleBy(x: unit, y: unit)
        drawShadow(pose, in: &canvas)

        var body = canvas
        let sy = pose.squashY, sx = 1 / pow(sy, 0.6)
        body.translateBy(x: 50, y: 86 - pose.lift)
        body.rotate(by: .degrees(pose.lean))
        body.scaleBy(x: sx, y: sy)
        body.translateBy(x: -50, y: -86)
        drawFeet(colors, in: &body)
        drawSprout(pose, colors: colors, in: &body)
        drawBody(colors, in: &body)
        drawFace(pose, colors: colors, in: &body)
        if pose.asleep { drawSnooze(pose, in: &canvas) }
    }

    private static func drawShadow(_ pose: BuddyPose, in canvas: inout GraphicsContext) {
        let scale = max(0.6, 1 - pose.lift / 30)
        let width = 54 * scale
        canvas.fill(Path(ellipseIn: CGRect(x: 50 - width / 2, y: 87.5 - 3 * scale, width: width, height: 6 * scale)),
                    with: .color(.black.opacity(0.28 * scale)))
    }

    private static func drawFeet(_ colors: BuddyColors, in canvas: inout GraphicsContext) {
        for side in [-1.0, 1.0] {
            canvas.fill(Path(ellipseIn: CGRect(x: 50 + side * 12 - 7, y: 80, width: 14, height: 8)), with: .color(colors.shade))
        }
    }

    private static func drawBody(_ colors: BuddyColors, in canvas: inout GraphicsContext) {
        let rect = CGRect(x: 19, y: 30, width: 62, height: 54)
        let shape = Path(ellipseIn: rect)
        canvas.fill(shape, with: skin(colors))
        // A soft top light, as if from a desk lamp.
        canvas.fill(Path(ellipseIn: CGRect(x: 30, y: 34, width: 26, height: 12)), with: .color(.white.opacity(0.22)))
    }

    /// The body's shading, reused for the eyelids so they match the skin around them.
    private static func skin(_ colors: BuddyColors) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [colors.body, colors.shade]), startPoint: CGPoint(x: 40, y: 34), endPoint: CGPoint(x: 62, y: 84))
    }

    private static func drawSprout(_ pose: BuddyPose, colors: BuddyColors, in canvas: inout GraphicsContext) {
        var sprout = canvas
        sprout.translateBy(x: 50, y: 32)
        sprout.rotate(by: .degrees(pose.sprout))
        var stem = Path()
        stem.move(to: .zero)
        stem.addQuadCurve(to: CGPoint(x: 1, y: -11), control: CGPoint(x: -2, y: -6))
        sprout.stroke(stem, with: .color(colors.sprout), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        for (side, tilt) in [(-1.0, -28.0), (1.0, 34.0)] {
            var leaf = sprout
            leaf.translateBy(x: 1, y: -11)
            leaf.rotate(by: .degrees(tilt + pose.sprout * 0.6))
            var shape = Path()
            shape.move(to: .zero)
            shape.addQuadCurve(to: CGPoint(x: side * 9, y: -1), control: CGPoint(x: side * 4, y: -6))
            shape.addQuadCurve(to: .zero, control: CGPoint(x: side * 5, y: 3))
            leaf.fill(shape, with: .color(colors.sprout))
        }
    }

    private static func drawFace(_ pose: BuddyPose, colors: BuddyColors, in canvas: inout GraphicsContext) {
        var face = canvas
        face.translateBy(x: pose.gazeX * 3, y: pose.gazeY * 2)
        for side in [-1.0, 1.0] {
            face.fill(Path(ellipseIn: CGRect(x: 50 + side * 17 - 5, y: 64, width: 10, height: 5)), with: .color(blush.opacity(0.32)))
            drawEye(at: CGPoint(x: 50 + side * 10.5, y: 56), pose: pose, colors: colors, in: &face)
        }
        var mouth = Path()
        if pose.asleep {
            mouth.addEllipse(in: CGRect(x: 48.6, y: 64.5, width: 2.8, height: 3))
        } else {
            mouth.move(to: CGPoint(x: 47, y: 64.5))
            mouth.addQuadCurve(to: CGPoint(x: 53, y: 64.5), control: CGPoint(x: 50, y: 67.5 + pose.squint * 1.5))
        }
        face.stroke(mouth, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    private static func drawEye(at center: CGPoint, pose: BuddyPose, colors: BuddyColors, in canvas: inout GraphicsContext) {
        let eye = CGRect(x: center.x - 3.6 + pose.gazeX * 2.2, y: center.y - 4.6 + pose.gazeY * 1.8, width: 7.2, height: 9.2)
        var drawn = canvas
        drawn.fill(Path(ellipseIn: eye), with: .color(ink))
        drawn.fill(Path(ellipseIn: CGRect(x: eye.maxX - 3.4, y: eye.minY + 1.4, width: 2.2, height: 2.2)), with: .color(.white.opacity(0.9)))
        // Lids are skin, clipped a touch larger than the eye so no dark rim shows when shut.
        let lidClip = Path(ellipseIn: eye.insetBy(dx: -1, dy: -1))
        drawn.clip(to: lidClip)
        let upper = eye.height * pose.lid * 0.85
        let lower = eye.height * max(pose.lid * 0.15, pose.squint * 0.45)
        drawn.fill(Path(CGRect(x: eye.minX - 1, y: eye.minY - 1, width: eye.width + 2, height: upper + 1)), with: skin(colors))
        drawn.fill(Path(CGRect(x: eye.minX - 1, y: eye.maxY - lower, width: eye.width + 2, height: lower + 1)), with: skin(colors))
    }

    private static func drawSnooze(_ pose: BuddyPose, in canvas: inout GraphicsContext) {
        for i in 0..<3 {
            let p = AmbientMotion.loop(pose.t, period: 3.6, phase: Double(i) / 3)
            let alpha = AmbientMotion.bell(p) * 0.7
            let point = CGPoint(x: 72 + p * 10 + AmbientMotion.wave(pose.t, period: 2.4, phase: Double(i) * 0.3) * 1.5, y: 34 - p * 16)
            canvas.draw(Text("z").font(.system(size: 6 + p * 5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.cream.opacity(alpha)), at: point)
        }
    }
}
