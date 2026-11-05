import ShelfCore
import SwiftUI

/// Charge as liquid in an upright cell. The surface moves only while charging.
struct BatteryWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model

    private var tier: InfoTier { InfoTier(context.size) }

    var body: some View {
        let stats = model.system
        WidgetCard {
            if let battery = stats.battery {
                BatteryFace(battery: battery, detailed: tier != .small)
            } else if stats.memory.values.isEmpty {
                Color.clear
            } else {
                WidgetPlaceholder(symbol: "powerplug", title: "No battery",
                                  detail: tier == .small ? nil : "This Mac runs on mains power.")
            }
        }
        .watchesSystemStats()
    }
}

private struct BatteryFace: View {
    let battery: BatteryInfo
    let detailed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: detailed ? Theme.Space.l : Theme.Space.m) {
            BatteryCell(level: battery.level, color: color, charging: battery.isCharging)
                .frame(width: detailed ? 66 : 54)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Battery")
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((battery.level * 100).rounded()))")
                        .font(Theme.Typeface.numeral(detailed ? 44 : 36))
                        .contentTransition(.numericText())
                    Text("%").font(Theme.Typeface.numeral(detailed ? 18 : 15)).foregroundStyle(Theme.textSecondary)
                }
                Text(state).font(Theme.Typeface.title(12)).foregroundStyle(stateColor).lineLimit(1)
                if let remaining {
                    Text(remaining).font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if detailed { health.padding(.top, Theme.Space.s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: battery.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue([InfoFormat.percent(battery.level), state, remaining].compactMap { $0 }.joined(separator: ", "))
    }

    private var health: some View {
        HStack(spacing: Theme.Space.l) {
            stat("Health", battery.health.map(InfoFormat.percent) ?? "--")
            stat("Cycles", battery.cycleCount.map(String.init) ?? "--")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.Typeface.numeral(15, weight: .medium))
            Text(label.uppercased()).font(Theme.Typeface.eyebrow).foregroundStyle(Theme.textTertiary)
        }
    }

    private var isLow: Bool { battery.level <= 0.2 && !battery.isPluggedIn }

    private var color: Color {
        if battery.isPluggedIn { return Theme.moss }
        return isLow ? Theme.ember : Theme.brass
    }

    private var stateColor: Color { isLow ? Theme.ember : Theme.textSecondary }

    private var state: String {
        if battery.isCharging { return "Charging" }
        if battery.isPluggedIn { return battery.level >= 0.99 ? "Charged" : "Not charging" }
        return "On battery"
    }

    private var remaining: String? {
        guard let minutes = battery.minutesRemaining else { return nil }
        if battery.isCharging { return "\(InfoFormat.duration(minutes: minutes)) to full" }
        return battery.isPluggedIn ? nil : "\(InfoFormat.duration(minutes: minutes)) left"
    }
}

/// Shell, terminal nub and the liquid inside.
private struct BatteryCell: View {
    let level: Double
    let color: Color
    let charging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let corner = width * 0.22
            VStack(spacing: 2) {
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.5))
                    .frame(width: width * 0.38, height: max(4, height * 0.045))
                ZStack {
                    liquid
                        .clipShape(.rect(cornerRadius: corner - 4, style: .continuous))
                        .padding(4)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 2)
                    LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .center)
                        .clipShape(.rect(cornerRadius: corner, style: .continuous))
                        .allowsHitTesting(false)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: width * 0.36, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var waves: Bool { charging && !reduceMotion }

    private var liquid: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !waves)) { timeline in
            let time = waves ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000) : 0
            let amplitude: CGFloat = waves ? 2.2 : 0
            ZStack {
                LiquidShape(level: level, phase: time * 1.7 + 1.9, amplitude: amplitude * 0.8)
                    .fill(color.opacity(0.4))
                LiquidShape(level: level, phase: time * 2.4, amplitude: amplitude)
                    .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

/// Fills from the bottom to `level`, with a sine surface.
private nonisolated struct LiquidShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let surface = rect.maxY - rect.height * CGFloat(min(1, max(0, level)))
        let wavelength = max(rect.width * 0.9, 1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            let y = surface + amplitude * CGFloat(sin(Double((x - rect.minX) / wavelength) * 2 * .pi + phase))
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: surface + amplitude * CGFloat(sin(Double(rect.width / wavelength) * 2 * .pi + phase))))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
