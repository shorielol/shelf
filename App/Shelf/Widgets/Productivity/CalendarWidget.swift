import ShelfCore
import SwiftUI

/// Today's date and what's on. Large shows the month with today ringed in ember and dots on busy days.
struct CalendarWidget: View {
    let context: WidgetContext
    @State private var store = CalendarStore.shared

    var body: some View {
        WidgetCard {
            TimelineView(.periodic(from: Calendar.current.startOfDay(for: Date()), by: 60)) { timeline in
                layout(now: timeline.date)
            }
        }
        .onAppear { store.activate() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar")
    }

    @ViewBuilder
    private func layout(now: Date) -> some View {
        if context.size.height > 300 {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                MonthGrid(month: now, today: now, busyDays: store.busyDays())
                Divider().overlay(Theme.hairline)
                agenda(now: now, limit: 4)
            }
        } else if context.isWide {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                DateBlock(date: now, numeralSize: 52)
                    .frame(width: 104, alignment: .leading)
                agenda(now: now, limit: 3)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                DateBlock(date: now, numeralSize: context.unit * 0.34)
                Spacer(minLength: Theme.Space.xs)
                nextUp(now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Small

    @ViewBuilder
    private func nextUp(now: Date) -> some View {
        if store.access != .granted {
            Button(store.access == .denied ? "Open Settings" : "Allow Calendar") { store.requestAccess() }
                .buttonStyle(.glass)
                .controlSize(.small)
        } else if let event = store.nextEvent(after: now), Calendar.current.isDate(event.start, inSameDayAs: now) || event.isHappening(at: now) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(event.color).frame(width: 7, height: 7)
                    Text(event.title).font(Theme.Typeface.title(12)).lineLimit(1)
                }
                Text(event.isHappening(at: now) ? "Now · until \(EventTime.clock(event.end))" : EventTime.clock(event.start))
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .accessibilityElement(children: .combine)
        } else {
            Text("Nothing else today")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agenda(now: Date, limit: Int) -> some View {
        if store.access != .granted {
            CalendarAccessPlaceholder(store: store, compact: !context.isWide || context.size.height < 300)
        } else {
            let today = store.events(on: now)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Eyebrow(text: "Today")
                    Spacer()
                    if today.count > limit {
                        Text("+\(today.count - limit) more").font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                if today.isEmpty {
                    Text("A clear day.")
                        .font(Theme.Typeface.display(15, weight: .regular))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(today.prefix(limit)) { AgendaRow(event: $0, now: now) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Weekday eyebrow over a big serif day number.
private struct DateBlock: View {
    let date: Date
    let numeralSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: date.formatted(.dateTime.weekday(.wide)), color: Theme.ember)
            Text(date.formatted(.dateTime.day()))
                .font(Theme.Typeface.display(numeralSize, weight: .regular))
                .displayTracking(numeralSize)
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(date.formatted(.dateTime.month(.wide)))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}

private struct AgendaRow: View {
    let event: CalendarEvent
    let now: Date

    var body: some View {
        let isPast = event.end <= now
        HStack(spacing: Theme.Space.s) {
            Text(event.isAllDay ? "All day" : EventTime.clock(event.start))
                .font(Theme.Typeface.numeral(11, weight: .medium))
                .foregroundStyle(event.isHappening(at: now) ? Theme.ember : Theme.textSecondary)
                .frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.color)
                .frame(width: 8, height: 8)
            Text(event.title)
                .font(Theme.Typeface.title(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .opacity(isPast ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(EventTime.range(event))")
    }
}

/// A month of days. Today gets an ember ring that draws itself in when the widget appears.
private struct MonthGrid: View {
    let month: Date
    let today: Date
    let busyDays: Set<Date>
    @State private var ringDrawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 4) {
            header
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .bold).width(.expanded))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                ForEach(weeks, id: \.self) { week in
                    GridRow {
                        ForEach(week, id: \.self) { day in cell(day) }
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion { ringDrawn = true } else {
                withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { ringDrawn = true }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(Theme.Typeface.display(20))
                .foregroundStyle(Theme.textPrimary)
            Text(month.formatted(.dateTime.year()))
                .font(Theme.Typeface.display(20, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func cell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isBusy = busyDays.contains(calendar.startOfDay(for: day))
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day()))
                .font(Theme.Typeface.numeral(12, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Theme.textPrimary : (inMonth ? Theme.textSecondary : Theme.textTertiary.opacity(0.5)))
            Circle()
                .fill(isToday ? Theme.ember : Theme.textSecondary)
                .frame(width: 3.5, height: 3.5)
                .opacity(isBusy && inMonth ? 1 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
        .background {
            if isToday {
                Circle()
                    .trim(from: 0, to: ringDrawn ? 1 : 0)
                    .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 27, height: 27)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(date: .long, time: .omitted) + (isToday ? ", today" : "") + (isBusy ? ", has events" : ""))
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Six rows of seven days, padded with the neighbouring months.
    private var weeks: [[Date]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.start) else { return [] }
        let start = firstWeek.start
        return (0..<6).map { row in
            (0..<7).compactMap { column in calendar.date(byAdding: .day, value: row * 7 + column, to: start) }
        }
    }
}
