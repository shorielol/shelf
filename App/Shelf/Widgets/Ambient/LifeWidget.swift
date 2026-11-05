import ShelfCore
import SwiftUI

/// Conway's Game of Life on a torus. Cells glow ember when alive and cool slowly after they die,
/// so the board reads like embers rather than flicker. Reseeds when it settles, and every two minutes.
struct LifeWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var simulation = LifeSimulation()

    private static let cellPitch: CGFloat = 8

    var body: some View {
        let columns = max(8, Int(context.size.width / Self.cellPitch))
        let rows = max(8, Int(context.size.height / Self.cellPitch))
        ZStack {
            Theme.graphite
            LifeDots(columns: columns, rows: rows)
            TimelineView(reduceMotion ? .animation(minimumInterval: 1, paused: false) : .animation(minimumInterval: 1.0 / 15.0, paused: false)) { timeline in
                let frame = simulation.frame(at: timeline.date, columns: columns, rows: rows, smooth: !reduceMotion)
                Canvas { canvas, size in
                    LifeArt.draw(frame, in: &canvas, size: size)
                }
                .overlay(alignment: .bottomLeading) {
                    if context.size.width > 250 {
                        Eyebrow(text: "Gen \(frame.generation.formatted())", color: Theme.textTertiary)
                            .padding(Theme.Space.m - 4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Game of Life")
                .accessibilityValue("\(frame.population) cells alive, generation \(frame.generation)")
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.widget, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .frame(width: context.size.width, height: context.size.height)
        .contentShape(.rect)
        .onTapGesture { simulation.reseedOnNextFrame() }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Scatters a new pattern")
    }
}

/// A faint dot where every cell could be. Static, so it only draws when the size changes.
private struct LifeDots: View {
    let columns: Int
    let rows: Int

    var body: some View {
        Canvas { canvas, size in
            let w = size.width / CGFloat(columns), h = size.height / CGFloat(rows)
            var dots = Path()
            for y in 0..<rows {
                for x in 0..<columns {
                    dots.addRect(CGRect(x: (CGFloat(x) + 0.5) * w - 0.5, y: (CGFloat(y) + 0.5) * h - 0.5, width: 1, height: 1))
                }
            }
            canvas.fill(dots, with: .color(.white.opacity(0.05)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame to draw: glow before and after the latest step, and how far between them we are.
nonisolated struct LifeFrame: Sendable {
    let columns: Int
    let rows: Int
    let before: [Float]
    let after: [Float]
    let progress: Float
    let generation: Int
    let population: Int
}

nonisolated enum LifeArt {
    private static let levels = 8

    /// Cells are grouped into a few brightness levels so the whole board is a handful of fills.
    static func draw(_ frame: LifeFrame, in canvas: inout GraphicsContext, size: CGSize) {
        guard frame.after.count == frame.columns * frame.rows, frame.before.count == frame.after.count else { return }
        let w = size.width / CGFloat(frame.columns), h = size.height / CGFloat(frame.rows)
        let inset = min(w, h) * 0.12
        let p = frame.progress * frame.progress * (3 - 2 * frame.progress)
        var paths = Array(repeating: Path(), count: levels)
        for i in 0..<frame.after.count {
            let value = frame.before[i] + (frame.after[i] - frame.before[i]) * p
            guard value > 0.04 else { continue }
            let level = min(levels - 1, Int(value * Float(levels)))
            let rect = CGRect(x: CGFloat(i % frame.columns) * w + inset, y: CGFloat(i / frame.columns) * h + inset,
                              width: w - inset * 2, height: h - inset * 2)
            paths[level].addRoundedRect(in: rect, cornerSize: CGSize(width: inset, height: inset))
        }
        for level in 0..<levels where !paths[level].isEmpty {
            let strength = (Double(level) + 0.5) / Double(levels)
            let color = strength > 0.85 ? Theme.ember : Theme.ember.mix(with: Theme.brass, by: 0.35 * (1 - strength))
            canvas.fill(paths[level], with: .color(color.opacity(0.15 + 0.85 * strength)))
        }
    }
}

/// Owns the board and turns wall-clock time into generations. Not observed: the timeline drives it.
final class LifeSimulation {
    private static let stepInterval: TimeInterval = 0.25
    private static let maxAge = 480  // two minutes of steps
    private static let maxCatchUp = 4

    private var board = LifeBoard(columns: 0, rows: 0)
    private var before: [Float] = []
    private var origin = Date()
    private var wantsReseed = false

    func reseedOnNextFrame() { wantsReseed = true }

    func frame(at date: Date, columns: Int, rows: Int, smooth: Bool) -> LifeFrame {
        if board.columns != columns || board.rows != rows {
            board = LifeBoard(columns: columns, rows: rows)
            board.reseed()
            before = Array(repeating: 0, count: columns * rows)
            // The seed counts as the first step, so it fades in from an empty board.
            origin = date.addingTimeInterval(-Self.stepInterval)
        }
        let target = Int(date.timeIntervalSince(origin) / Self.stepInterval)
        var steps = target - board.generation
        if steps > Self.maxCatchUp {
            // Woke from sleep or was hidden: don't replay minutes of history, just carry on.
            origin = origin.addingTimeInterval(Double(steps - 1) * Self.stepInterval)
            steps = 1
        }
        for _ in 0..<max(0, steps) {
            before = board.glow
            if wantsReseed || board.isStagnant || board.age >= Self.maxAge {
                wantsReseed = false
                board.reseed()
            } else {
                board.step()
            }
        }
        let elapsed = date.timeIntervalSince(origin) / Self.stepInterval - Double(board.generation)
        return LifeFrame(columns: columns, rows: rows, before: before, after: board.glow,
                         progress: smooth ? Float(min(1, max(0, elapsed))) : 1,
                         generation: board.totalGenerations, population: board.population)
    }
}

/// The automaton itself. `glow` is 1 for live cells and decays for dead ones.
nonisolated struct LifeBoard {
    let columns: Int
    let rows: Int
    private(set) var glow: [Float]
    private(set) var generation = 0
    private(set) var age = 0
    private(set) var totalGenerations = 0
    private(set) var population = 0
    private var cells: [UInt8]
    private var scratch: [UInt8]
    private var recent: [Int] = []

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        cells = Array(repeating: 0, count: columns * rows)
        scratch = cells
        glow = Array(repeating: 0, count: columns * rows)
    }

    /// Settled into a still life or a two-step blinker, or nearly died out.
    var isStagnant: Bool {
        population < max(4, columns * rows / 60) || recent.dropLast().contains(recent.last ?? -1)
    }

    mutating func reseed() {
        var rng = SystemRandomNumberGenerator()
        for i in cells.indices { cells[i] = Double.random(in: 0..<1, using: &rng) < 0.3 ? 1 : 0 }
        age = 0
        recent = []
        finishStep()
    }

    mutating func step() {
        for y in 0..<rows {
            let up = ((y - 1 + rows) % rows) * columns, row = y * columns, down = ((y + 1) % rows) * columns
            for x in 0..<columns {
                let left = (x - 1 + columns) % columns, right = (x + 1) % columns
                let n = Int(cells[up + left]) + Int(cells[up + x]) + Int(cells[up + right])
                    + Int(cells[row + left]) + Int(cells[row + right])
                    + Int(cells[down + left]) + Int(cells[down + x]) + Int(cells[down + right])
                let alive = cells[row + x] == 1
                scratch[row + x] = (n == 3 || (alive && n == 2)) ? 1 : 0
            }
        }
        swap(&cells, &scratch)
        age += 1
        finishStep()
    }

    private mutating func finishStep() {
        generation += 1
        totalGenerations += 1
        var count = 0
        for i in cells.indices {
            if cells[i] == 1 { glow[i] = 1; count += 1 } else { glow[i] *= 0.5 }
        }
        population = count
        var hasher = Hasher()
        hasher.combine(cells)
        recent.append(hasher.finalize())
        if recent.count > 3 { recent.removeFirst() }
    }
}
