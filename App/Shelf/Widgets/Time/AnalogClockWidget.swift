import SwiftUI

/// A wall clock in three faces. The railway face does what station clocks do: the seconds hand sweeps
/// round in 58.5 s, waits at twelve, and releases the minute hand with a small clunk.
struct AnalogClockWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Face: String, CaseIterable {
        case minimal, railway, bauhaus
        var label: String { rawValue.capitalized }
    }

    private var face: Face { Face(rawValue: context.string("face", "minimal")) ?? .minimal }
    private var showsSeconds: Bool { context.bool("seconds", true) }
    private var showsDate: Bool { context.size.height >= 300 }

    var body: some View {
        WidgetCard(tint: nil, padding: context.unit < 200 ? 10 : Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        ClockDial(face: face)
                        hands(diameter: diameter)
                    }
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showsDate { dateLine }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Analog clock")
        .accessibilityValue(Text(Date(), style: .time))
    }

    /// Only the railway sweep needs frames; everything else ticks once a second (or every 10 s without seconds).
    @ViewBuilder
    private func hands(diameter: CGFloat) -> some View {
        if face == .railway && showsSeconds && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                ClockHands(face: face, angles: angles(at: timeline.date), diameter: diameter, showsSeconds: true)
            }
        } else {
            TimelineView(AlignedSchedule(interval: showsSeconds ? 1 : 10)) { timeline in
                ClockHands(face: face, angles: angles(at: timeline.date), diameter: diameter, showsSeconds: showsSeconds)
            }
        }
    }

    private var dateLine: some View {
        TimelineView(AlignedSchedule(interval: 60)) { timeline in
            HStack(alignment: .firstTextBaseline) {
                Text(timeline.date.formatted(.dateTime.weekday(.wide)))
                    .font(Theme.Typeface.display(18))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Eyebrow(text: timeline.date.formatted(.dateTime.day().month(.abbreviated)))
            }
            .padding(.horizontal, Theme.Space.xs)
        }
    }

    // MARK: Hand angles

    private func angles(at date: Date) -> HandAngles {
        let reading = ClockReading(date)
        let seconds = Double(reading.second) + reading.fraction
        switch face {
        case .railway where !reduceMotion:
            // Seconds: a full turn in 58.5 s, then a pause at twelve. Minutes jump when it's released.
            let sweep = min(1, seconds / 58.5) * 360
            let clunk = seconds < 0.6 ? 1.6 * exp(-seconds * 9) * cos(seconds * 34) : 0
            let minute = Double(reading.minute) * 6 + clunk
            let hour = Double(reading.hour % 12) * 30 + Double(reading.minute) * 0.5
            return HandAngles(hour: hour, minute: minute, second: showsSeconds ? sweep : 0)
        default:
            let minute = Double(reading.minute) * 6 + Double(reading.second) * 0.1
            let hour = Double(reading.hour % 12) * 30 + Double(reading.minute) * 0.5 + Double(reading.second) / 120
            return HandAngles(hour: hour, minute: minute, second: Double(reading.second) * 6)
        }
    }
}

nonisolated struct HandAngles: Equatable {
    let hour: Double
    let minute: Double
    let second: Double
}

// MARK: - Dial

/// The static face. Drawn once per size; the hands are a separate layer so ticking never redraws the dial.
private struct ClockDial: View {
    let face: AnalogClockWidget.Face

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            switch face {
            case .minimal: drawMinimal(&context, center: center, radius: radius)
            case .railway: drawRailway(&context, center: center, radius: radius)
            case .bauhaus: drawBauhaus(&context, center: center, radius: radius)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawMinimal(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(.black.opacity(0.16)))
        context.stroke(disc.strokedPath(.init(lineWidth: 1)), with: .color(.white.opacity(0.14)))
        for index in 0..<60 {
            let isHour = index % 5 == 0
            let length = radius * (isHour ? 0.11 : 0.045)
            tick(&context, center: center, angle: Double(index) * 6, from: radius * 0.92 - length, to: radius * 0.92,
                 width: isHour ? max(1.6, radius * 0.025) : 0.8, color: .white.opacity(isHour ? 0.85 : 0.3))
        }
    }

    private func drawRailway(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let bezel = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(bezel, with: .linearGradient(Gradient(colors: [Color(white: 0.78), Color(white: 0.42)]),
                                                  startPoint: CGPoint(x: center.x, y: center.y - radius), endPoint: CGPoint(x: center.x, y: center.y + radius)))
        let inner = radius * 0.95
        let dial = Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
        context.fill(dial, with: .radialGradient(Gradient(colors: [.white, Color(white: 0.93)]), center: center, startRadius: 0, endRadius: inner))
        for index in 0..<60 {
            let isHour = index % 5 == 0
            let length = inner * (isHour ? 0.24 : 0.07)
            tick(&context, center: center, angle: Double(index) * 6, from: inner * 0.92 - length, to: inner * 0.92,
                 width: inner * (isHour ? 0.07 : 0.022), color: Color(white: 0.08), cap: .butt)
        }
    }

    private func drawBauhaus(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let dial = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(dial, with: .color(Theme.cream))
        let ring = radius * 0.78
        for hour in 0..<12 {
            let angle = Double(hour) * 30
            let point = Self.point(center: center, angle: angle, distance: ring)
            let mark = radius * 0.13
            switch hour {
            case 0:
                context.fill(Path(ellipseIn: CGRect(x: point.x - mark / 2, y: point.y - mark / 2, width: mark, height: mark)), with: .color(Theme.ember))
            case 3:
                context.fill(Path(CGRect(x: point.x - mark * 0.42, y: point.y - mark * 0.42, width: mark * 0.84, height: mark * 0.84)), with: .color(Self.bauhausBlue))
            case 6:
                var triangle = Path()
                triangle.move(to: CGPoint(x: point.x, y: point.y - mark * 0.5))
                triangle.addLine(to: CGPoint(x: point.x + mark * 0.55, y: point.y + mark * 0.45))
                triangle.addLine(to: CGPoint(x: point.x - mark * 0.55, y: point.y + mark * 0.45))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(Self.bauhausYellow))
            case 9:
                tick(&context, center: center, angle: angle, from: ring - mark * 0.5, to: ring + mark * 0.5, width: mark * 0.32, color: Theme.graphite, cap: .butt)
            default:
                let dot = radius * 0.035
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)), with: .color(Theme.graphite))
            }
        }
    }

    static let bauhausBlue = Color(red: 0.16, green: 0.32, blue: 0.62)
    static let bauhausYellow = Color(red: 0.94, green: 0.74, blue: 0.20)

    private func tick(_ context: inout GraphicsContext, center: CGPoint, angle: Double, from inner: CGFloat, to outer: CGFloat,
                      width: CGFloat, color: Color, cap: CGLineCap = .round) {
        var path = Path()
        path.move(to: Self.point(center: center, angle: angle, distance: inner))
        path.addLine(to: Self.point(center: center, angle: angle, distance: outer))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: cap))
    }

    /// Clockwise from twelve.
    static func point(center: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: center.x + sin(radians) * distance, y: center.y - cos(radians) * distance)
    }
}

// MARK: - Hands

private struct ClockHands: View {
    let face: AnalogClockWidget.Face
    let angles: HandAngles
    let diameter: CGFloat
    let showsSeconds: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            var shadow = context
            shadow.translateBy(x: radius * 0.012, y: radius * 0.03)
            shadow.opacity = face == .minimal ? 0.35 : 0.22
            drawHands(&shadow, center: center, radius: radius, tint: .black)
            drawHands(&context, center: center, radius: radius, tint: nil)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private func drawHands(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color?) {
        let style = HandStyle(face: face)
        hand(&context, center: center, angle: angles.hour, length: radius * style.hourLength, tail: radius * 0.12,
             width: radius * style.hourWidth, color: tint ?? style.ink, cap: style.cap)
        hand(&context, center: center, angle: angles.minute, length: radius * style.minuteLength, tail: radius * 0.14,
             width: radius * style.minuteWidth, color: tint ?? style.ink, cap: style.cap)
        if showsSeconds { secondsHand(&context, center: center, radius: radius, tint: tint) }
        let hub = radius * (face == .railway ? 0.05 : 0.045)
        context.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
                     with: .color(tint ?? (face == .bauhaus ? ClockDial.bauhausBlue : style.secondColor)))
    }

    private func secondsHand(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color?) {
        let color = tint ?? HandStyle(face: face).secondColor
        let length = radius * (face == .railway ? 0.62 : 0.84)
        hand(&context, center: center, angle: angles.second, length: length, tail: radius * 0.24,
             width: radius * (face == .railway ? 0.026 : 0.016), color: color, cap: .butt)
        guard face != .minimal else { return }
        // The lollipop on the railway hand, a counterweight disc on the bauhaus one.
        let discRadius = radius * (face == .railway ? 0.105 : 0.05)
        let tip = ClockDial.point(center: center, angle: angles.second, distance: face == .railway ? length : -radius * 0.2)
        context.fill(Path(ellipseIn: CGRect(x: tip.x - discRadius, y: tip.y - discRadius, width: discRadius * 2, height: discRadius * 2)), with: .color(color))
    }

    private func hand(_ context: inout GraphicsContext, center: CGPoint, angle: Double, length: CGFloat, tail: CGFloat,
                      width: CGFloat, color: Color, cap: CGLineCap) {
        var path = Path()
        path.move(to: ClockDial.point(center: center, angle: angle, distance: -tail))
        path.addLine(to: ClockDial.point(center: center, angle: angle, distance: length))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: cap))
    }
}

/// Proportions and colours of the hands for each face.
private struct HandStyle {
    let ink: Color
    let secondColor: Color
    let hourLength: CGFloat
    let minuteLength: CGFloat
    let hourWidth: CGFloat
    let minuteWidth: CGFloat
    let cap: CGLineCap

    init(face: AnalogClockWidget.Face) {
        switch face {
        case .minimal:
            self.init(ink: Theme.textPrimary, secondColor: Theme.ember, hourLength: 0.5, minuteLength: 0.78,
                      hourWidth: 0.055, minuteWidth: 0.038, cap: .round)
        case .railway:
            self.init(ink: Color(white: 0.08), secondColor: Color(red: 0.86, green: 0.13, blue: 0.10), hourLength: 0.6, minuteLength: 0.88,
                      hourWidth: 0.1, minuteWidth: 0.075, cap: .butt)
        case .bauhaus:
            self.init(ink: Theme.graphite, secondColor: Theme.ember, hourLength: 0.48, minuteLength: 0.74,
                      hourWidth: 0.075, minuteWidth: 0.045, cap: .butt)
        }
    }

    private init(ink: Color, secondColor: Color, hourLength: CGFloat, minuteLength: CGFloat,
                 hourWidth: CGFloat, minuteWidth: CGFloat, cap: CGLineCap) {
        self.ink = ink
        self.secondColor = secondColor
        self.hourLength = hourLength
        self.minuteLength = minuteLength
        self.hourWidth = hourWidth
        self.minuteWidth = minuteWidth
        self.cap = cap
    }
}
