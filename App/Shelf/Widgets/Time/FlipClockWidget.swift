import SwiftUI

/// Split-flap clock. Each card is two halves on a hinge: when the value changes, the old top half
/// folds down over the new one, darkening as it turns away from the light.
struct FlipClockWidget: View {
    let context: WidgetContext

    enum Finish: String, CaseIterable {
        case graphite, cream, ember
        var label: String { rawValue.capitalized }
    }

    private var finish: Finish { Finish(rawValue: context.string("finish", "graphite")) ?? .graphite }
    private var uses24Hour: Bool { context.bool("24h", false) }
    private var showsSeconds: Bool { context.bool("seconds", false) && context.size.width >= 300 }
    private var playsSound: Bool { context.bool("sound", false) }
    private var showsDate: Bool { context.size.height >= 300 }

    var body: some View {
        WidgetCard(tint: finish == .ember ? Theme.ember.opacity(0.4) : nil, padding: padding) {
            TimelineView(AlignedSchedule(interval: showsSeconds ? 1 : 60)) { timeline in
                let reading = ClockReading(timeline.date)
                VStack(spacing: Theme.Space.m) {
                    cards(reading)
                    if showsDate { dateLine(timeline.date) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: reading.minute) {
                    if playsSound { Sounds.shared.play(.clack, volume: 0.35) }
                }
                .accessibilityElement()
                .accessibilityLabel("Flip clock")
                .accessibilityValue(timeline.date.formatted(date: .omitted, time: showsSeconds ? .standard : .shortened))
            }
        }
    }

    private var padding: CGFloat { context.unit < 200 ? 12 : Theme.Space.m }

    private func cards(_ reading: ClockReading) -> some View {
        let gap = max(4, context.unit * 0.035)
        let metrics = cardMetrics(gap: gap)
        let hour = uses24Hour ? String(format: "%02d", reading.hour) : String(reading.hour12)
        return HStack(spacing: gap) {
            FlipCard(value: hour, finish: finish, size: metrics.main)
                .overlay(alignment: .bottomLeading) {
                    if !uses24Hour { meridiem(reading.isPM, card: metrics.main) }
                }
            FlipCard(value: String(format: "%02d", reading.minute), finish: finish, size: metrics.main)
            if showsSeconds {
                FlipCard(value: String(format: "%02d", reading.second), finish: finish, size: metrics.seconds)
            }
        }
    }

    /// Card sizes that fill the width, capped so the cards stay a little taller than wide.
    private func cardMetrics(gap: CGFloat) -> (main: CGSize, seconds: CGSize) {
        let width = context.size.width - padding * 2
        let height = context.size.height - padding * 2 - (showsDate ? 44 : 0)
        let units: CGFloat = showsSeconds ? 2.6 : 2
        let gaps = gap * (showsSeconds ? 2 : 1)
        let cardWidth = min((width - gaps) / units, height * 1.15)
        let cardHeight = min(height, cardWidth * (context.unit < 200 ? 1.4 : 1.12))
        let main = CGSize(width: cardWidth, height: cardHeight)
        return (main, CGSize(width: cardWidth * 0.6, height: cardHeight * 0.6))
    }

    private func meridiem(_ isPM: Bool, card: CGSize) -> some View {
        Text(isPM ? "PM" : "AM")
            .font(.system(size: max(8, card.height * 0.085), weight: .bold).width(.expanded))
            .foregroundStyle(finish.ink.opacity(0.55))
            .padding(card.height * 0.07)
            .accessibilityHidden(true)
    }

    private func dateLine(_ date: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(Theme.Typeface.display(20))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Eyebrow(text: date.formatted(.dateTime.day().month(.wide)))
        }
        .padding(.horizontal, Theme.Space.xs)
    }
}

extension FlipClockWidget.Finish {
    var card: Color {
        switch self {
        case .graphite: Color(red: 0.15, green: 0.145, blue: 0.135)
        case .cream: Theme.cream
        case .ember: Color(red: 0.80, green: 0.32, blue: 0.18)
        }
    }

    var ink: Color {
        switch self {
        case .graphite: Theme.cream
        case .cream: Theme.graphite
        case .ember: Color(red: 1, green: 0.95, blue: 0.9)
        }
    }
}

/// One split-flap card. Holds the previous value while the flaps are mid-turn.
struct FlipCard: View {
    let value: String
    let finish: FlipClockWidget.Finish
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String?
    @State private var previous: String?
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 0

    private static let fallDuration = 0.2
    private static let settleDuration = 0.26

    var body: some View {
        let current = shown ?? value
        let old = previous ?? current
        let hinge = max(1, size.height * 0.012)
        VStack(spacing: hinge) {
            ZStack {
                half(current, top: true)
                half(old, top: true)
                    .overlay(shade(opacity: -topAngle / 90 * 0.55, top: true))
                    .rotation3DEffect(.degrees(topAngle), axis: (1, 0, 0), anchor: .bottom, perspective: 0.45)
                    .opacity(topAngle <= -89.5 ? 0 : 1)
            }
            .zIndex(1)
            ZStack {
                half(old, top: false)
                    .overlay(shade(opacity: (1 - bottomAngle / 90) * 0.3 * (previous == nil ? 0 : 1), top: false))
                half(current, top: false)
                    .overlay(shade(opacity: bottomAngle / 90 * 0.45, top: false))
                    .rotation3DEffect(.degrees(bottomAngle), axis: (1, 0, 0), anchor: .top, perspective: 0.45)
                    .opacity(previous == nil || bottomAngle < 89.5 ? 1 : 0)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(alignment: .center) { hingeShadow(hinge) }
        .overlay { pins(hinge) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: size.height * 0.04, y: size.height * 0.025)
        .onChange(of: value) { old, new in flip(from: shown ?? old, to: new) }
        .accessibilityHidden(true)
    }

    // MARK: Motion

    private func flip(from old: String, to new: String) {
        guard old != new else { return }
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.25)) { shown = new }
            previous = nil
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            previous = old
            shown = new
            topAngle = 0
            bottomAngle = 90
        }
        withAnimation(.easeIn(duration: Self.fallDuration)) {
            topAngle = -90
        } completion: {
            withAnimation(.spring(response: Self.settleDuration, dampingFraction: 0.7)) {
                bottomAngle = 0
            } completion: {
                if shown == new { previous = nil }
            }
        }
    }

    // MARK: Parts

    private var radius: CGFloat { size.height * 0.085 }

    /// Half of the full card face, clipped at the hinge.
    private func half(_ text: String, top: Bool) -> some View {
        face(text)
            .frame(width: size.width, height: size.height)
            .frame(width: size.width, height: (size.height - max(1, size.height * 0.012)) / 2, alignment: top ? .top : .bottom)
            .clipped()
    }

    private func face(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [finish.card.mix(with: .white, by: 0.06), finish.card, finish.card.mix(with: .black, by: 0.12)],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            Text(text)
                .font(.system(size: fontSize(for: text), weight: .bold, design: .rounded).monospacedDigit())
                .tracking(-fontSize(for: text) * 0.02)
                .foregroundStyle(finish.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func fontSize(for text: String) -> CGFloat {
        min(size.height * 0.72, size.width * (text.count > 1 ? 0.62 : 0.8))
    }

    /// Darkens a flap as it turns away; heavier near the hinge, where the light can't reach.
    private func shade(opacity: Double, top: Bool) -> some View {
        LinearGradient(colors: [.black.opacity(opacity * 0.6), .black.opacity(opacity)],
                       startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            .clipShape(.rect(cornerRadius: radius * 0.6))
            .allowsHitTesting(false)
    }

    private func hingeShadow(_ hinge: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.55))
            .frame(height: hinge + 1)
    }

    /// The two little pins the flaps hang from.
    private func pins(_ hinge: CGFloat) -> some View {
        let pin = Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.22)], startPoint: .top, endPoint: .bottom))
            .frame(width: max(2.5, size.width * 0.025), height: max(5, size.height * 0.07))
        return HStack {
            pin
            Spacer()
            pin
        }
        .padding(.horizontal, -size.width * 0.006)
        .allowsHitTesting(false)
    }
}
