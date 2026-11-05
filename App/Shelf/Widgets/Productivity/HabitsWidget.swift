import ShelfCore
import SwiftUI

/// Up to three habits, each a contribution grid of recent weeks. Tap today's square to mark it done.
struct HabitsWidget: View {
    let context: WidgetContext

    static let colors: [Color] = [Theme.ember, Theme.brass, Theme.moss]
    private static let maxHabits = 3

    private var names: [String] {
        let parsed = context.string("habits", "Read, Move, Write")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(parsed.prefix(Self.maxHabits))
    }

    var body: some View {
        WidgetCard {
            TimelineView(.periodic(from: Calendar.current.startOfDay(for: Date()), by: 3_600)) { timeline in
                if names.isEmpty {
                    WidgetPlaceholder(symbol: "square.grid.3x3.square", title: "Add a habit", detail: "Name up to three in settings.")
                } else {
                    GeometryReader { proxy in
                        grid(in: proxy.size, today: timeline.date)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Habits")
    }

    @ViewBuilder
    private func grid(in size: CGSize, today: Date) -> some View {
        let stacked = size.height > 220 || names.count == 1
        let spacing = stacked ? Theme.Space.s + 4 : Theme.Space.m
        let count = CGFloat(names.count)
        let cellSize = stacked
            ? CGSize(width: size.width, height: (size.height - spacing * (count - 1)) / count)
            : CGSize(width: (size.width - spacing * (count - 1)) / count, height: size.height)
        let layout = stacked ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HabitColumn(
                    name: name,
                    color: Self.colors[index % Self.colors.count],
                    done: Set(context.config.strings("done.\(index)")),
                    today: today,
                    size: cellSize,
                    inlineHeader: stacked
                ) { toggled in
                    context.update("done.\(index)", .strings(toggled))
                }
            }
        }
    }
}

/// One habit: a header with name, streak and a check button, then the grid.
private struct HabitColumn: View {
    let name: String
    let color: Color
    let done: Set<String>
    let today: Date
    let size: CGSize
    let inlineHeader: Bool
    let save: ([String]) -> Void

    private static let headerHeight: CGFloat = 24
    private static let keepDays = 400

    var body: some View {
        let todayKey = HabitDay.key(today)
        let isDoneToday = done.contains(todayKey)
        let streak = HabitDay.streak(done: done, today: today)
        let headerBlock: CGFloat = inlineHeader ? Self.headerHeight : Self.headerHeight + 16
        let metrics = GridMetrics(available: CGSize(width: size.width, height: size.height - headerBlock - 6))
        VStack(alignment: .leading, spacing: 6) {
            header(isDoneToday: isDoneToday, streak: streak)
            ContributionGrid(metrics: metrics, done: done, today: today, color: color, isDoneToday: isDoneToday) { toggle(todayKey) }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(streak) day streak, \(isDoneToday ? "done today" : "not done today")")
    }

    @ViewBuilder
    private func header(isDoneToday: Bool, streak: Int) -> some View {
        let streakView = HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 9)).foregroundStyle(streak > 0 ? color : Theme.textTertiary)
            Text("\(streak)").font(Theme.Typeface.numeral(12)).contentTransition(.numericText()).foregroundStyle(Theme.textPrimary)
            Text(streak == 1 ? "day" : "days").font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
        }
        .animation(Theme.Motion.lively, value: streak)
        if inlineHeader {
            HStack(spacing: Theme.Space.s) {
                nameLabel
                streakView
                Spacer(minLength: 0)
                checkButton(isDoneToday)
            }
            .frame(height: Self.headerHeight)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    nameLabel
                    Spacer(minLength: 0)
                    checkButton(isDoneToday)
                }
                .frame(height: Self.headerHeight)
                streakView.frame(height: 14)
            }
        }
    }

    private var nameLabel: some View {
        Text(name).font(Theme.Typeface.title(12.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
    }

    private func checkButton(_ isDone: Bool) -> some View {
        Button { toggle(HabitDay.key(today)) } label: {
            ZStack {
                Circle().strokeBorder(isDone ? color : Theme.textTertiary, lineWidth: 1.5)
                Circle().fill(color).scaleEffect(isDone ? 1 : 0.3).opacity(isDone ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            .frame(width: 24, height: 24)
            .contentShape(.circle)
            .animation(Theme.Motion.lively, value: isDone)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isDone ? "Unmark \(name) for today" : "Mark \(name) done today")
    }

    private func toggle(_ key: String) {
        var next = done
        if next.contains(key) {
            next.remove(key)
        } else {
            next.insert(key)
            Sounds.shared.play(.pop, volume: 0.3)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: today).map { HabitDay.key($0) } ?? ""
        save(next.filter { $0 >= cutoff }.sorted())
    }
}

/// Cell size and how many weeks fit.
private struct GridMetrics {
    let cell: CGFloat
    let gap: CGFloat
    let weeks: Int

    init(available: CGSize) {
        let pitch = min(14, max(5, available.height / 7))
        gap = max(1.5, (pitch * 0.2).rounded(.down))
        cell = pitch - gap
        weeks = max(1, Int((available.width + gap) / pitch))
    }

    var pitch: CGFloat { cell + gap }
    var size: CGSize { CGSize(width: CGFloat(weeks) * pitch - gap, height: 7 * pitch - gap) }
}

/// Weeks run left to right, ending with this week. Past days are drawn in one Canvas;
/// today is a real button laid over its square so it can pop when tapped.
private struct ContributionGrid: View {
    let metrics: GridMetrics
    let done: Set<String>
    let today: Date
    let color: Color
    let isDoneToday: Bool
    let toggleToday: () -> Void

    var body: some View {
        let cells = HabitDay.cells(weeks: metrics.weeks, today: today, done: done)
        let todayCell = cells.first { $0.isToday }
        Canvas { context, _ in
            for cell in cells where !cell.isFuture && !cell.isToday {
                let rect = CGRect(x: CGFloat(cell.column) * metrics.pitch, y: CGFloat(cell.row) * metrics.pitch,
                                  width: metrics.cell, height: metrics.cell)
                let path = Path(roundedRect: rect, cornerRadius: metrics.cell * 0.28, style: .continuous)
                context.fill(path, with: .color(cell.isDone ? color.opacity(0.92) : Color.white.opacity(0.07)))
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        .overlay(alignment: .topLeading) {
            if let todayCell {
                TodayCell(size: metrics.cell, color: color, isDone: isDoneToday, action: toggleToday)
                    .position(x: CGFloat(todayCell.column) * metrics.pitch + metrics.cell / 2,
                              y: CGFloat(todayCell.row) * metrics.pitch + metrics.cell / 2)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TodayCell: View {
    let size: CGFloat
    let color: Color
    let isDone: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(isDone ? color : Color.clear)
                .strokeBorder(color, lineWidth: isDone ? 0 : 1.2)
                .frame(width: size, height: size)
                .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? false : isDone) { square, scale in
                    square.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.7, duration: 0.14, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
                .shadow(color: isDone ? color.opacity(0.7) : .clear, radius: 3)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Day keys ("yyyy-MM-dd") and grid placement.
enum HabitDay {
    struct Cell {
        let column: Int
        let row: Int
        let isDone: Bool
        let isToday: Bool
        let isFuture: Bool
    }

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func cells(weeks: Int, today: Date, done: Set<String>, calendar: Calendar = .current) -> [Cell] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let first = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeek) else { return [] }
        let todayStart = calendar.startOfDay(for: today)
        var result: [Cell] = []
        result.reserveCapacity(weeks * 7)
        var day = first
        for index in 0..<(weeks * 7) {
            let start = calendar.startOfDay(for: day)
            result.append(Cell(column: index / 7, row: index % 7, isDone: done.contains(key(start, calendar: calendar)),
                               isToday: start == todayStart, isFuture: start > todayStart))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Consecutive days done, counting back from today (or yesterday, if today isn't done yet).
    static func streak(done: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if !done.contains(key(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while done.contains(key(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
