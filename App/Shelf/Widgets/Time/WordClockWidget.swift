import ShelfCore
import SwiftUI

/// The time spelled out on a letter grid, five minutes at a time, with a dot in each corner
/// for the minutes in between. Letters fade up and down like a lamp behind a stencil.
struct WordClockWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesEmber: Bool { context.string("glow", "cream") == "ember" }
    private var lit: Color { usesEmber ? Color(red: 1, green: 0.55, blue: 0.36) : Theme.cream }
    private var glow: Color { usesEmber ? Theme.ember : Theme.brass.opacity(0.7) }

    private static let rows = WordClock.grid.map { Array($0) }

    var body: some View {
        WidgetCard(tint: Theme.graphite.opacity(0.6), padding: 0) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let dotInset = max(9, side * 0.055)
                let gridSide = side - dotInset * 4.2
                TimelineView(AlignedSchedule(interval: 60)) { timeline in
                    let reading = ClockReading(timeline.date)
                    let step = reading.minute / 5 * 5
                    let cells = WordClock.litCells(hour: reading.hour, minute: step)
                    ZStack {
                        corners(count: reading.minute - step, side: side, inset: dotInset)
                        ZStack {
                            DimGrid(rows: Self.rows, cell: gridSide / 11)
                            litLetters(cells, cell: gridSide / 11)
                        }
                        .frame(width: gridSide, height: gridSide)
                    }
                    .frame(width: side, height: side)
                    .animation(reduceMotion ? .easeInOut(duration: 0.3) : .easeInOut(duration: 1.1), value: cells)
                    .animation(.easeInOut(duration: 0.6), value: reading.minute)
                    .accessibilityElement()
                    .accessibilityLabel("Word clock")
                    .accessibilityValue(WordClock.phrase(hour: reading.hour, minute: step).capitalized)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func litLetters(_ cells: Set<WordClock.Cell>, cell: CGFloat) -> some View {
        let ordered = cells.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        return ZStack {
            ForEach(ordered, id: \.self) { item in
                Text(String(Self.rows[item.row][item.column]))
                    .font(.system(size: cell * 0.6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lit)
                    .position(x: (CGFloat(item.column) + 0.5) * cell, y: (CGFloat(item.row) + 0.5) * cell)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .shadow(color: glow.opacity(0.75), radius: cell * 0.28)
        .shadow(color: glow.opacity(0.3), radius: cell * 0.9)
        .accessibilityHidden(true)
    }

    /// Minutes past the five-minute step: one dot per minute, clockwise from top left.
    private func corners(count: Int, side: CGFloat, inset: CGFloat) -> some View {
        let positions = [CGPoint(x: inset, y: inset), CGPoint(x: side - inset, y: inset),
                         CGPoint(x: side - inset, y: side - inset), CGPoint(x: inset, y: side - inset)]
        let dot = max(3.5, side * 0.022)
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < count ? lit : Color.white.opacity(0.1))
                    .frame(width: dot, height: dot)
                    .shadow(color: index < count ? glow : .clear, radius: dot)
                    .position(positions[index])
            }
        }
        .accessibilityHidden(true)
    }
}

/// Every letter, unlit. Drawn as one Canvas since it never changes.
private struct DimGrid: View {
    let rows: [[Character]]
    let cell: CGFloat

    var body: some View {
        Canvas { context, _ in
            for (row, letters) in rows.enumerated() {
                for (column, letter) in letters.enumerated() {
                    let text = Text(String(letter))
                        .font(.system(size: cell * 0.6, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.13))
                    context.draw(context.resolve(text), at: CGPoint(x: (CGFloat(column) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
