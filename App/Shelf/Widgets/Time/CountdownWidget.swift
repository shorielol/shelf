import ShelfCore
import SwiftUI

/// Days to an event. The ring is the share of the wait still left, measured from when the widget
/// was added, so it empties steadily however far away the date is.
struct CountdownWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallbackTarget = Date().addingTimeInterval(30 * 86_400)
    @State private var fallbackCreated = Date()
    @State private var burstStart: Date?
    @State private var showsSeconds = false

    enum Style: String, CaseIterable {
        case ring, page
        var label: String { self == .ring ? "Ring" : "Calendar page" }
    }

    private var title: String {
        let text = context.string("title", "Launch").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "Countdown" : text
    }

    private var style: Style { Style(rawValue: context.string("style", "ring")) ?? .ring }
    private var target: Date { context.config.double("target").map(Date.init(timeIntervalSince1970:)) ?? fallbackTarget }
    private var created: Date { context.config.double("created").map(Date.init(timeIntervalSince1970:)) ?? fallbackCreated }

    var body: some View {
        WidgetCard(padding: context.unit < 200 ? 12 : Theme.Space.m) {
            TimelineView(AlignedSchedule(interval: showsSeconds ? 1 : 60)) { timeline in
                let now = timeline.date
                let parts = Countdown.parts(from: now, to: target)
                content(now: now, parts: parts)
                    .onChange(of: parts.isPast) { wasPast, isPast in
                        if !wasPast && isPast { celebrate() }
                    }
                    .onChange(of: needsSeconds(now), initial: true) { _, needed in showsSeconds = needed }
                    .accessibilityElement()
                    .accessibilityLabel("Countdown to \(title)")
                    .accessibilityValue(spoken(parts, now: now))
            }
        }
        .overlay {
            if let burstStart { ConfettiBurst(start: burstStart).clipShape(.rect(cornerRadius: Theme.Radius.widget)) }
        }
        .task(id: burstStart) {
            guard burstStart != nil else { return }
            try? await Task.sleep(for: .seconds(ConfettiBurst.duration))
            burstStart = nil
        }
        .onAppear(perform: seedConfig)
    }

    // MARK: Layout

    @ViewBuilder
    private func content(now: Date, parts: Countdown.Parts) -> some View {
        if context.isWide {
            HStack(spacing: Theme.Space.m) {
                indicator(now: now, parts: parts).frame(width: context.size.height - 32)
                details(now: now, parts: parts)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if style == .ring { Eyebrow(text: title) }
                indicator(now: now, parts: parts).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func indicator(now: Date, parts: Countdown.Parts) -> some View {
        switch style {
        case .ring:
            ZStack {
                ring(remaining: remainingFraction(now))
                headline(now: now, parts: parts)
            }
            .aspectRatio(1, contentMode: .fit)
        case .page:
            CalendarPage(title: context.isWide ? target.formatted(.dateTime.month(.abbreviated)) : title) {
                headline(now: now, parts: parts)
            }
        }
    }

    private func details(now: Date, parts: Countdown.Parts) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Countdown")
            Text(title)
                .font(Theme.Typeface.display(22))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(target.formatted(date: .complete, time: .omitted))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !parts.isPast { units(parts) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The big number in the middle: days, then a clock on the last day, then "Today".
    @ViewBuilder
    private func headline(now: Date, parts: Countdown.Parts) -> some View {
        let ink = style == .page ? Theme.graphite : Theme.textPrimary
        let sub = style == .page ? Theme.graphite.opacity(0.6) : Theme.textSecondary
        let size = context.unit * (context.isWide ? 0.3 : 0.26)
        VStack(spacing: 0) {
            if parts.isPast {
                Image(systemName: "sparkles").font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(Theme.ember)
                Text(Calendar.current.isDate(now, inSameDayAs: target) ? "Today" : "Passed")
                    .font(Theme.Typeface.display(size * 0.55))
                    .foregroundStyle(ink)
            } else if parts.days > 0 {
                Text("\(parts.days)").font(Theme.Typeface.numeral(size, weight: .bold)).foregroundStyle(ink)
                Text(parts.days == 1 ? "day" : "days").font(Theme.Typeface.caption).foregroundStyle(sub)
            } else {
                Text(String(format: "%d:%02d:%02d", parts.hours, parts.minutes, parts.seconds))
                    .font(Theme.Typeface.numeral(size * 0.5, weight: .bold)).foregroundStyle(ink)
                Text("to go").font(Theme.Typeface.caption).foregroundStyle(sub)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, Theme.Space.s)
        .contentTransition(.numericText(countsDown: true))
    }

    private func units(_ parts: Countdown.Parts) -> some View {
        HStack(spacing: Theme.Space.m) {
            unit(parts.days, "days")
            unit(parts.hours, "hrs")
            unit(parts.minutes, "min")
        }
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(Theme.Typeface.numeral(20)).foregroundStyle(Theme.textPrimary)
            Text(label.uppercased()).font(Theme.Typeface.eyebrow).foregroundStyle(Theme.textTertiary)
        }
    }

    private func ring(remaining: Double) -> some View {
        let line = max(5, context.unit * 0.045)
        return ZStack {
            Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: remaining)
                .stroke(LinearGradient(colors: [Theme.ember, Theme.brass], startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.Motion.standard, value: remaining)
        }
        .accessibilityHidden(true)
    }

    // MARK: State

    private func remainingFraction(_ now: Date) -> Double {
        let total = target.timeIntervalSince(created)
        guard total > 0 else { return 0 }
        return min(1, max(0, target.timeIntervalSince(now) / total))
    }

    private func needsSeconds(_ now: Date) -> Bool {
        let left = target.timeIntervalSince(now)
        return left > 0 && left < 86_400
    }

    /// Writes the default target and the creation time the first time a real instance appears.
    private func seedConfig() {
        if context.config.double("target") == nil { context.update("target", .number(fallbackTarget.timeIntervalSince1970)) }
        if context.config.double("created") == nil { context.update("created", .number(Date().timeIntervalSince1970)) }
        let celebrated = context.config.double("celebrated") ?? 0
        let now = Date()
        if now >= target, Calendar.current.isDate(now, inSameDayAs: target), celebrated != target.timeIntervalSince1970 {
            celebrate()
        }
    }

    private func celebrate() {
        context.update("celebrated", .number(target.timeIntervalSince1970))
        guard !reduceMotion else { return }
        burstStart = Date()
    }

    private func spoken(_ parts: Countdown.Parts, now: Date) -> String {
        if parts.isPast { return Calendar.current.isDate(now, inSameDayAs: target) ? "Today" : "Passed" }
        if parts.days > 0 { return "\(parts.days) days, \(parts.hours) hours left" }
        return "\(parts.hours) hours, \(parts.minutes) minutes left"
    }
}

/// A tear-off calendar page: a bound ember header and a paper body.
private struct CalendarPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let header = max(24, proxy.size.height * 0.24)
            VStack(spacing: 0) {
                Text(title.uppercased())
                    .font(Theme.Typeface.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(maxWidth: .infinity)
                    .frame(height: header)
                    .background(LinearGradient(colors: [Theme.ember, Theme.ember.mix(with: .black, by: 0.18)], startPoint: .top, endPoint: .bottom))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [Theme.cream, Theme.cream.mix(with: .black, by: 0.08)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .top) { rings(width: proxy.size.width).offset(y: -5) }
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
    }

    /// The binder rings where the page was torn from.
    private func rings(width: CGFloat) -> some View {
        HStack(spacing: width * 0.34) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.4)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 5, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}
