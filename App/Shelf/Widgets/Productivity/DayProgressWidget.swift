import ShelfCore
import SwiftUI

/// How far through the day, week, month and year you are. Once a minute a bead of light runs along each bar.
struct DayProgressWidget: View {
    let context: WidgetContext

    var body: some View {
        WidgetCard {
            TimelineView(.everyMinute) { timeline in
                let rows = ProgressRow.all(at: timeline.date)
                Group {
                    if context.isWide { bars(rows, minute: timeline.date) } else { rings(rows, minute: timeline.date) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Progress")
                .accessibilityValue(rows.map { "\($0.title) \($0.percent) percent" }.joined(separator: ", "))
            }
        }
    }

    private func bars(_ rows: [ProgressRow], minute: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow(text: row.title)
                        Text(row.caption).font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                        Spacer()
                        PercentText(percent: row.percent, size: 13)
                    }
                    LiquidBar(fraction: row.fraction, color: row.color, trigger: minute, delay: Double(index) * 0.12)
                        .frame(height: 8)
                }
            }
        }
    }

    private func rings(_ rows: [ProgressRow], minute: Date) -> some View {
        Grid(horizontalSpacing: Theme.Space.s, verticalSpacing: Theme.Space.s) {
            ForEach([0, 2], id: \.self) { start in
                GridRow {
                    ForEach(start..<(start + 2), id: \.self) { index in
                        let row = rows[index]
                        VStack(spacing: 3) {
                            ZStack {
                                LiquidRing(fraction: row.fraction, color: row.color, trigger: minute, delay: Double(index) * 0.12)
                                PercentText(percent: row.percent, size: 12)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Eyebrow(text: row.title, color: Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

private struct ProgressRow {
    let title: String
    let caption: String
    let fraction: Double
    let color: Color

    var percent: Int { Int((fraction * 100).rounded(.down)) }

    static func all(at date: Date) -> [ProgressRow] {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: date)
        return [
            ProgressRow(title: "Day", caption: hoursLeft(at: date), fraction: DayProgress.fraction(of: .day, at: date), color: Theme.ember),
            ProgressRow(title: "Week", caption: "Week \(week)", fraction: DayProgress.fraction(of: .week, at: date), color: Theme.brass),
            ProgressRow(title: "Month", caption: date.formatted(.dateTime.month(.wide)), fraction: DayProgress.fraction(of: .month, at: date), color: Theme.moss),
            ProgressRow(title: "Year", caption: date.formatted(.dateTime.year()), fraction: DayProgress.fraction(of: .year, at: date), color: Theme.cream),
        ]
    }

    private static func hoursLeft(at date: Date) -> String {
        guard let end = Calendar.current.dateInterval(of: .day, for: date)?.end else { return "" }
        let minutes = Int(end.timeIntervalSince(date) / 60)
        return "\(minutes / 60)h \(minutes % 60)m left"
    }
}

private struct PercentText: View {
    let percent: Int
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(percent)").font(Theme.Typeface.numeral(size)).contentTransition(.numericText())
            Text("%").font(.system(size: size * 0.7, weight: .semibold, design: .rounded)).foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Theme.textPrimary)
        .animation(Theme.Motion.standard, value: percent)
    }
}

/// A filled capsule with a glassy top light and a sheen that sweeps through it whenever `trigger` changes.
private struct LiquidBar: View {
    let fraction: Double
    let color: Color
    let trigger: Date
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.height, proxy.size.width * fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .top) {
                        Capsule().fill(Color.white.opacity(0.28)).frame(height: proxy.size.height * 0.32).padding(.horizontal, 3).padding(.top, 1)
                    }
                    .overlay { if !reduceMotion { Sheen(trigger: trigger, delay: delay) } }
                    .clipShape(Capsule())
                    .frame(width: width)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: fraction)
    }
}

/// The ring version for the small size, with the same once-a-minute sheen travelling around the arc.
private struct LiquidRing: View {
    let fraction: Double
    let color: Color
    let trigger: Date
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = StrokeStyle(lineWidth: 6, lineCap: .round)
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.005, fraction))
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center, startAngle: .zero, endAngle: .degrees(360 * fraction)), style: line)
            if !reduceMotion {
                Circle()
                    .stroke(Color.white, style: line)
                    .keyframeAnimator(initialValue: -0.2, trigger: trigger) { ring, head in
                        ring.mask(
                            Circle().trim(from: max(0, head * fraction - 0.06), to: min(fraction, max(0, head * fraction)))
                                .stroke(style: line)
                        )
                        .opacity(head > 0 && head < 1 ? 0.55 : 0)
                    } keyframes: { _ in
                        LinearKeyframe(-0.2, duration: delay)
                        CubicKeyframe(1.05, duration: 1.4)
                    }
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(3)
        .aspectRatio(1, contentMode: .fit)
        .animation(.easeInOut(duration: 0.8), value: fraction)
    }
}

private struct Sheen: View {
    let trigger: Date
    let delay: Double

    var body: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(24, proxy.size.width * 0.35))
                .keyframeAnimator(initialValue: -0.4, trigger: trigger) { band, phase in
                    band.offset(x: phase * travel)
                } keyframes: { _ in
                    LinearKeyframe(-0.4, duration: delay)
                    CubicKeyframe(1.1, duration: 1.4)
                }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
