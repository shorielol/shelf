import ShelfCore
import SwiftUI

/// CPU, memory and disk as three rings, with recent CPU and memory history on larger sizes.
struct SystemWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tier: InfoTier { InfoTier(context.size) }

    var body: some View {
        let stats = model.system
        let meters = [
            Meter(label: "CPU", value: stats.cpu.values.last, color: Theme.ember),
            Meter(label: "Memory", value: stats.memory.values.last, color: Theme.brass),
            Meter(label: "Disk", value: stats.memory.values.isEmpty ? nil : stats.disk, color: Theme.moss),
        ]
        WidgetCard {
            switch tier {
            case .small: small(meters)
            case .medium: medium(meters, stats: stats)
            case .large: large(meters, stats: stats)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: meters.map { $0.value ?? -1 })
        .watchesSystemStats()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System")
        .accessibilityValue(meters.map { "\($0.label) \($0.text)" }.joined(separator: ", "))
    }

    private func small(_ meters: [Meter]) -> some View {
        VStack(spacing: Theme.Space.s) {
            HStack { Eyebrow(text: "System"); Spacer() }
            NestedRings(meters: meters).frame(width: 84, height: 84).frame(maxHeight: .infinity)
            HStack(spacing: 0) {
                ForEach(meters) { meter in
                    VStack(spacing: 1) {
                        Text(meter.text).font(Theme.Typeface.numeral(14)).foregroundStyle(meter.color)
                            .contentTransition(.numericText())
                        Text(meter.shortLabel).font(Theme.Typeface.eyebrow).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func medium(_ meters: [Meter], stats: SystemStats) -> some View {
        HStack(spacing: Theme.Space.m) {
            NestedRings(meters: meters).frame(width: 112, height: 112)
            VStack(spacing: 10) {
                HistoryRow(meter: meters[0], history: stats.cpu)
                HistoryRow(meter: meters[1], history: stats.memory)
                HStack {
                    Text("Disk").font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(meters[2].text) used").font(Theme.Typeface.numeral(12, weight: .medium)).foregroundStyle(meters[2].color)
                }
            }
        }
    }

    private func large(_ meters: [Meter], stats: SystemStats) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow(text: "System")
            HStack(spacing: 0) {
                ForEach(meters) { meter in
                    VStack(spacing: Theme.Space.s) {
                        ZStack {
                            GaugeRing(value: meter.value ?? 0, color: meter.color, lineWidth: 9)
                            Text(meter.text).font(Theme.Typeface.numeral(17)).contentTransition(.numericText())
                        }
                        .frame(width: 84, height: 84)
                        Text(meter.label).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            HistoryRow(meter: meters[0], history: stats.cpu, chartHeight: 52)
            HistoryRow(meter: meters[1], history: stats.memory, chartHeight: 52)
        }
    }
}

private struct Meter: Identifiable {
    let label: String
    let value: Double?
    let color: Color

    var id: String { label }
    var text: String { value.map(InfoFormat.percent) ?? "--" }
    var shortLabel: String { label == "Memory" ? "MEM" : label.uppercased() }
}

/// Label, current value and a sparkline of the last eighty seconds.
private struct HistoryRow: View {
    let meter: Meter
    let history: SampleHistory
    var chartHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(meter.label).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(meter.text).font(Theme.Typeface.numeral(12, weight: .medium)).foregroundStyle(meter.color)
                    .contentTransition(.numericText())
            }
            InfoSparkline(history: history, color: meter.color, ceiling: 1).frame(height: chartHeight)
        }
    }
}

/// Three rings one inside the other, outermost first.
private struct NestedRings: View {
    let meters: [Meter]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = side * 0.1
            ZStack {
                ForEach(Array(meters.enumerated()), id: \.element.id) { index, meter in
                    let inset = CGFloat(index) * line * 1.3
                    GaugeRing(value: meter.value ?? 0, color: meter.color, lineWidth: line)
                        .padding(inset)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A ring etched with ticks like an instrument bezel. The fill brightens toward its leading cap.
private struct GaugeRing: View {
    let value: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let clamped = min(1, max(0.004, value))
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .stroke(.black.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth * 0.45, dash: [0.8, 4.2]))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * clamped)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}
