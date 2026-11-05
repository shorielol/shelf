import AppKit
import ShelfCore
import SwiftUI

/// The next event with a live countdown. A fuse burns down through the last hour before it starts.
struct UpNextWidget: View {
    let context: WidgetContext
    @State private var store = CalendarStore.shared

    var body: some View {
        WidgetCard {
            if store.access != .granted {
                CalendarAccessPlaceholder(store: store, compact: !context.isWide)
            } else {
                TimelineView(.periodic(from: Date(), by: 15)) { timeline in
                    if let event = store.nextEvent(after: timeline.date) {
                        content(event, now: timeline.date)
                    } else {
                        empty
                    }
                }
            }
        }
        .onAppear { store.activate() }
    }

    @ViewBuilder
    private func content(_ event: CalendarEvent, now: Date) -> some View {
        Group {
            if context.isWide { wide(event, now: now) } else { square(event, now: now) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Up next: \(event.title), \(EventTime.relative(to: event, from: now)), \(EventTime.range(event))")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Eyebrow(text: "Up Next")
            Spacer(minLength: 0)
            Text("Nothing on the calendar.")
                .font(Theme.Typeface.display(context.isWide ? 20 : 16, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            Text("Next two weeks are clear")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Layouts

    private func square(_ event: CalendarEvent, now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Eyebrow(text: event.isHappening(at: now) ? "Now" : "Up Next", color: event.isHappening(at: now) ? Theme.ember : Theme.textSecondary)
                Spacer()
                if let url = event.meetingURL { JoinButton(url: url, compact: true) }
            }
            Spacer(minLength: 0)
            CountdownText(event: event, now: now, size: 34)
            Fuse(event: event, now: now).frame(height: 6)
            Text(event.title)
                .font(Theme.Typeface.title(13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .padding(.top, 2)
            Text(EventTime.range(event))
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func wide(_ event: CalendarEvent, now: Date) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Eyebrow(text: event.isHappening(at: now) ? "Now" : "Up Next", color: event.isHappening(at: now) ? Theme.ember : Theme.textSecondary)
                Spacer(minLength: 0)
                CountdownText(event: event, now: now, size: 40)
                Fuse(event: event, now: now).frame(height: 6)
            }
            .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(event.color).frame(width: 7, height: 7)
                    Text(event.calendarTitle).font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Text(event.title)
                    .font(Theme.Typeface.display(17))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                detail("clock", EventTime.range(event))
                if let location = event.location, event.meetingURL == nil || !location.contains("://") {
                    detail("mappin.and.ellipse", location)
                }
                Spacer(minLength: 0)
                if let url = event.meetingURL { JoinButton(url: url, compact: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).lineLimit(1)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.textTertiary)
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(Theme.textSecondary)
        .labelStyle(.titleAndIcon)
    }
}

/// "12 min" set as a big rounded numeral with a small unit.
private struct CountdownText: View {
    let event: CalendarEvent
    let now: Date
    let size: CGFloat

    var body: some View {
        let parts = Self.parts(event, now: now)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if !parts.prefix.isEmpty {
                Text(parts.prefix).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            }
            Text(parts.value)
                .font(Theme.Typeface.numeral(size))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
            Text(parts.unit).font(Theme.Typeface.title(size * 0.36)).foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .animation(Theme.Motion.standard, value: parts.value)
    }

    static func parts(_ event: CalendarEvent, now: Date) -> (prefix: String, value: String, unit: String) {
        if event.isHappening(at: now) {
            let left = max(1, Int((event.end.timeIntervalSince(now) / 60).rounded(.up)))
            return left < 60 ? ("ends in", "\(left)", "min") : ("ends in", "\(left / 60)", "h")
        }
        let minutes = max(0, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes == 0 { return ("", "Now", "") }
        if minutes < 60 { return ("in", "\(minutes)", "min") }
        if minutes < 24 * 60 {
            let hours = Double(minutes) / 60
            return ("in", hours < 10 ? hours.formatted(.number.precision(.fractionLength(0...1))) : "\(minutes / 60)", "h")
        }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: event.start)).day ?? 1
        return days <= 1 ? ("tomorrow", event.start.formatted(.dateTime.hour().minute()), "") : ("in", "\(days)", "days")
    }
}

/// Before the event, an ember fuse that shortens over the final hour, with a glowing tip.
/// During the event, a brass bar that fills as it runs.
private struct Fuse: View {
    let event: CalendarEvent
    let now: Date
    private static let lead: TimeInterval = 3_600

    var body: some View {
        let isLive = event.isHappening(at: now)
        let fraction = isLive
            ? now.timeIntervalSince(event.start) / max(1, event.end.timeIntervalSince(event.start))
            : min(1, max(0, event.start.timeIntervalSince(now) / Self.lead))
        GeometryReader { proxy in
            let width = max(proxy.size.height, proxy.size.width * fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10)).frame(height: 3)
                Capsule()
                    .fill(LinearGradient(colors: isLive ? [Theme.brass.opacity(0.7), Theme.brass] : [Theme.brass.opacity(0.6), Theme.ember],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: width, height: 3)
                if !isLive {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 5, height: 5)
                        .shadow(color: Theme.ember, radius: 3)
                        .shadow(color: Theme.ember.opacity(0.8), radius: 6)
                        .offset(x: width - 5)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.linear(duration: 1), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct JoinButton: View {
    let url: URL
    let compact: Bool

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            if compact {
                Image(systemName: "video.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            } else {
                Label("Join", systemImage: "video.fill")
                    .font(Theme.Typeface.title(12))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
            }
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
        .modifier(JoinSurface(compact: compact))
        .accessibilityLabel("Join meeting")
        .help(url.host() ?? "Join")
    }
}

private struct JoinSurface: ViewModifier {
    let compact: Bool
    func body(content: Content) -> some View {
        if compact { content.glassCircle(tint: Theme.ember, interactive: true) } else { content.glassCapsule(tint: Theme.ember, interactive: true) }
    }
}
