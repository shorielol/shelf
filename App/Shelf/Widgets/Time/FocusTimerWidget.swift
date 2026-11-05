import ShelfCore
import SwiftUI

/// Pomodoro timer (or a plain stopwatch) on a kitchen-timer dial. All running state lives in the
/// widget's config as timestamps, so a timer keeps its place across quits and relaunches.
struct FocusTimerWidget: View {
    let context: WidgetContext

    private static let roundsPerSet = FocusTimerState.roundsPerSet

    private var state: FocusTimerState { FocusTimerState(config: context.config) }

    var body: some View {
        let state = state
        WidgetCard(padding: context.unit < 200 ? 12 : Theme.Space.m) {
            if state.isRunning {
                TimelineView(AlignedSchedule(interval: 1)) { timeline in
                    content(state, now: timeline.date)
                }
            } else {
                content(state, now: Date())
            }
        }
        .task(id: state.endsAt) { await waitForPhaseEnd(state) }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ state: FocusTimerState, now: Date) -> some View {
        let reading = state.reading(at: now)
        Group {
            if context.isWide {
                HStack(spacing: Theme.Space.m) {
                    TimerDial(reading: reading, tint: state.tint, unit: context.size.height - 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: state.isStopwatch ? "Stopwatch" : "Focus timer")
                        Text(state.phaseTitle).font(Theme.Typeface.display(22)).foregroundStyle(Theme.textPrimary)
                        if !state.isStopwatch { roundDots(state, size: 8) }
                        Spacer(minLength: 0)
                        controls(state, size: 32)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: Theme.Space.s) {
                    TimerDial(reading: reading, tint: state.tint, unit: min(context.size.width, context.size.height) - 70) {
                        if !state.isStopwatch { roundDots(state, size: 5) }
                    }
                    controls(state, size: 30)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.isStopwatch ? "Stopwatch" : "Focus timer, \(state.phaseTitle)")
        .accessibilityValue(reading.spoken)
    }

    private func roundDots(_ state: FocusTimerState, size: CGFloat) -> some View {
        HStack(spacing: size * 0.8) {
            ForEach(0..<Self.roundsPerSet, id: \.self) { index in
                Circle()
                    .fill(index < state.round ? Theme.ember : Color.white.opacity(0.14))
                    .overlay(Circle().strokeBorder(index == state.round && state.phase == .work ? Theme.ember.opacity(0.8) : .clear, lineWidth: 1))
                    .frame(width: size, height: size)
            }
        }
        .animation(Theme.Motion.lively, value: state.round)
        .accessibilityElement()
        .accessibilityLabel("Round \(min(state.round + 1, Self.roundsPerSet)) of \(Self.roundsPerSet)")
    }

    private func controls(_ state: FocusTimerState, size: CGFloat) -> some View {
        HStack(spacing: Theme.Space.s) {
            TimeControlButton(symbol: "arrow.counterclockwise", label: "Reset", size: size * 0.86) { apply(state.reset(now: Date())) }
            TimeControlButton(symbol: state.isRunning ? "pause.fill" : "play.fill", label: state.isRunning ? "Pause" : "Start",
                              size: size, tint: state.tint) {
                apply(state.isRunning ? state.paused(now: Date()) : state.started(now: Date()))
            }
        }
    }

    // MARK: State changes

    private func apply(_ changes: [String: ConfigValue]) {
        for (key, value) in changes { context.update(key, value) }
    }

    /// Sleeps until the running phase ends, then moves on. Cancelled when the view goes away or the phase changes.
    private func waitForPhaseEnd(_ state: FocusTimerState) async {
        guard let endsAt = state.endsAt else { return }
        let wait = endsAt.timeIntervalSinceNow
        if wait > 0 {
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        }
        // Only chime if we're on time; a phase that ended while the app was closed just advances quietly.
        if Date().timeIntervalSince(endsAt) < 5 { Sounds.shared.play(.pop) }
        apply(state.advanced())
    }
}

// MARK: - Dial

/// A ring that drains, a bead at its head, and minute ticks round the outside like a kitchen timer.
private struct TimerDial<Inner: View>: View {
    let reading: FocusTimerState.Reading
    let tint: Color
    let unit: CGFloat
    @ViewBuilder var inner: Inner

    var body: some View {
        let side = max(60, unit)
        let line = max(5, side * 0.06)
        ZStack {
            ticks(side: side)
            Circle().stroke(Color.white.opacity(0.09), lineWidth: line).padding(side * 0.11)
            Circle()
                .trim(from: 0, to: reading.fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(side * 0.11)
            bead(side: side, line: line)
            VStack(spacing: 4) {
                Text(reading.text)
                    .font(Theme.Typeface.numeral(side * (reading.text.count > 5 ? 0.17 : 0.21), weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(countsDown: !reading.countsUp))
                inner
            }
        }
        .frame(width: side, height: side)
        .animation(.linear(duration: 0.25), value: reading.fraction)
    }

    private func ticks(side: CGFloat) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for index in 0..<60 {
                let major = index % 5 == 0
                let angle = Double(index) * 6 * .pi / 180
                let outer = radius * 0.99, inner = radius * (major ? 0.92 : 0.95)
                var path = Path()
                path.move(to: CGPoint(x: center.x + sin(angle) * inner, y: center.y - cos(angle) * inner))
                path.addLine(to: CGPoint(x: center.x + sin(angle) * outer, y: center.y - cos(angle) * outer))
                context.stroke(path, with: .color(.white.opacity(major ? 0.4 : 0.16)), lineWidth: major ? 1.4 : 0.8)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private func bead(side: CGFloat, line: CGFloat) -> some View {
        let radius = side / 2 - side * 0.11
        let angle = reading.fraction * 2 * .pi
        return Circle()
            .fill(Theme.cream)
            .frame(width: line * 0.8, height: line * 0.8)
            .shadow(color: tint, radius: line * 0.8)
            .offset(x: sin(angle) * radius, y: -cos(angle) * radius)
            .opacity(reading.fraction > 0.002 ? 1 : 0)
            .accessibilityHidden(true)
    }
}

extension TimerDial where Inner == EmptyView {
    init(reading: FocusTimerState.Reading, tint: Color, unit: CGFloat) {
        self.init(reading: reading, tint: tint, unit: unit) { EmptyView() }
    }
}
