import ShelfCore
import SwiftUI

/// The sun's arc for today and tonight's moon, worked out on the Mac with no network once the place is known.
struct SunMoonWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @State private var lookupFailed = false

    private var city: String { context.string("city", "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tier: InfoTier { InfoTier(context.size) }

    var body: some View {
        WidgetCard {
            if let spot {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    SunMoonFace(spot: spot, now: timeline.date, tier: tier)
                }
            } else if !city.isEmpty {
                if lookupFailed {
                    WidgetPlaceholder(symbol: "mappin.slash", title: "Couldn't find \(city)",
                                      detail: tier == .small ? nil : "Check the spelling, or your connection.")
                } else {
                    WidgetPlaceholder(symbol: "globe.europe.africa", title: "Finding \(city)")
                }
            } else {
                InfoLocationNeeded(compact: tier == .small)
            }
        }
        .task(id: city) { await resolveCity() }
        .onChange(of: model.weather.currentLocation, initial: true) { _, here in cacheHere(here) }
    }

    /// A typed city uses its cached coordinates. "Here" prefers the live fix, then the last one we saw.
    private var spot: Spot? {
        let config = context.config
        let resolved = config.string("resolved")
        if city.isEmpty, let here = model.weather.currentLocation {
            return Spot(name: "My Location", latitude: here.latitude, longitude: here.longitude, timeZone: .current)
        }
        guard resolved == city.lowercased(), let latitude = config.double("lat"), let longitude = config.double("lon") else { return nil }
        let zone = TimeZone(identifier: config.string("tz") ?? "") ?? TimeZone(secondsFromGMT: Int((longitude / 15).rounded()) * 3600) ?? .current
        return Spot(name: city.isEmpty ? "My Location" : (config.string("placeName") ?? city),
                    latitude: latitude, longitude: longitude, timeZone: city.isEmpty ? .current : zone)
    }

    private func resolveCity() async {
        lookupFailed = false
        guard !city.isEmpty, context.config.string("resolved") != city.lowercased() else { return }
        let query = city
        do {
            guard let place = try await InfoGeocoder.lookup(query) else {
                lookupFailed = true
                return
            }
            guard !Task.isCancelled else { return }
            context.update("lat", .number(place.latitude))
            context.update("lon", .number(place.longitude))
            context.update("placeName", .string(place.name))
            context.update("tz", .string(place.timeZone ?? ""))
            context.update("resolved", .string(query.lowercased()))
        } catch {
            if !Task.isCancelled { lookupFailed = true }
        }
    }

    /// Remember the last fix so the widget still works offline or before location comes back.
    private func cacheHere(_ here: WeatherService.Place?) {
        guard city.isEmpty, let here else { return }
        let config = context.config
        let moved = abs((config.double("lat") ?? .infinity) - here.latitude) > 0.02
            || abs((config.double("lon") ?? .infinity) - here.longitude) > 0.02
        guard moved || config.string("resolved") != "" else { return }
        context.update("lat", .number(here.latitude))
        context.update("lon", .number(here.longitude))
        context.update("resolved", .string(""))
    }
}

private struct Spot {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
}

/// The layouts. Everything here is computed from the date and the coordinates.
private struct SunMoonFace: View {
    let spot: Spot
    let now: Date
    let tier: InfoTier

    var body: some View {
        let solar = SolarDay(now: now, latitude: spot.latitude, longitude: spot.longitude)
        let moon = MoonPhase(date: now)
        Group {
            switch tier {
            case .small: small(solar, moon)
            case .medium: medium(solar, moon)
            case .large: large(solar, moon)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sun and moon, \(spot.name)")
        .accessibilityValue(spoken(solar, moon))
    }

    private var flipsMoon: Bool { spot.latitude < 0 }

    private func small(_ solar: SolarDay, _ moon: MoonPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Eyebrow(text: spot.name)
                Spacer(minLength: 4)
                MoonDisc(phase: moon, flipped: flipsMoon).frame(width: 26, height: 26)
            }
            SunArc(phase: solar.phase).frame(maxHeight: .infinity)
            times(solar, size: 13)
            Text("\(moon.name) · \(InfoFormat.percent(moon.illumination))")
                .font(Theme.Typeface.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func medium(_ solar: SolarDay, _ moon: MoonPhase) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: spot.name)
                SunArc(phase: solar.phase).frame(maxHeight: .infinity)
                times(solar, size: 14)
            }
            Rectangle().fill(Theme.hairline).frame(width: 1).padding(.vertical, 6)
            VStack(spacing: 6) {
                MoonDisc(phase: moon, flipped: flipsMoon).frame(width: 74, height: 74)
                    .frame(maxHeight: .infinity)
                Text(moon.name).font(Theme.Typeface.display(13)).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(InfoFormat.percent(moon.illumination)) lit")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 104)
        }
    }

    private func large(_ solar: SolarDay, _ moon: MoonPhase) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
            Eyebrow(text: spot.name)
            SunArc(phase: solar.phase).frame(height: 120)
            times(solar, size: 16)
            if let daylight = solar.daylight {
                Text("\(InfoFormat.duration(minutes: Int(daylight / 60))) of daylight")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 4)
            HStack(spacing: Theme.Space.m) {
                MoonDisc(phase: moon, flipped: flipsMoon).frame(width: 108, height: 108)
                VStack(alignment: .leading, spacing: 4) {
                    Text(moon.name).font(Theme.Typeface.display(19))
                    Text("\(InfoFormat.percent(moon.illumination)) illuminated")
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    upcoming("Full moon", inDays: MoonCalendar.days(from: moon, to: 0.5))
                    upcoming("New moon", inDays: MoonCalendar.days(from: moon, to: 0))
                }
                .frame(maxHeight: 108)
            }
            Spacer(minLength: 0)
        }
    }

    private func times(_ solar: SolarDay, size: CGFloat) -> some View {
        HStack {
            timeLabel("sunrise.fill", solar.sunrise, size: size)
            Spacer(minLength: 4)
            timeLabel("sunset.fill", solar.sunset, size: size)
        }
    }

    private func timeLabel(_ symbol: String, _ date: Date?, size: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(Theme.brass)
            Text(date.map(format) ?? "--")
                .font(Theme.Typeface.numeral(size, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func upcoming(_ label: String, inDays days: Double) -> some View {
        let date = now.addingTimeInterval(days * 86_400)
        return HStack {
            Text(label).font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(date.formatted(Date.FormatStyle(timeZone: spot.timeZone).month(.abbreviated).day()))
                .font(Theme.Typeface.numeral(12, weight: .medium))
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: spot.timeZone))
    }

    private func spoken(_ solar: SolarDay, _ moon: MoonPhase) -> String {
        var parts: [String] = []
        if let sunrise = solar.sunrise { parts.append("Sunrise \(format(sunrise))") }
        if let sunset = solar.sunset { parts.append("sunset \(format(sunset))") }
        parts.append("\(moon.name), \(InfoFormat.percent(moon.illumination)) illuminated")
        return parts.joined(separator: ", ")
    }
}

private enum MoonCalendar {
    /// Days until the phase next reaches `target` (0 new, 0.5 full).
    static func days(from moon: MoonPhase, to target: Double) -> Double {
        var delta = (target - moon.phase).truncatingRemainder(dividingBy: 1)
        if delta <= 0.0001 { delta += 1 }
        return delta * MoonPhase.synodicMonth
    }
}

// MARK: Sun

/// Where we are between the surrounding sunrise and sunset, whichever UTC day they fall on.
private struct SolarDay {
    enum Phase {
        case day(Double)
        case night(Double)
        case polarDay
        case polarNight
    }

    let phase: Phase
    let sunrise: Date?
    let sunset: Date?

    init(now: Date, latitude: Double, longitude: Double) {
        let events = (-1...1)
            .compactMap { SunTimes(date: now.addingTimeInterval(Double($0) * 86_400), latitude: latitude, longitude: longitude) }
            .flatMap { [(date: $0.sunrise, rises: true), (date: $0.sunset, rises: false)] }
            .sorted { $0.date < $1.date }
        let last = events.last { $0.date <= now }
        let next = events.first { $0.date > now }
        if let last, let next, last.rises != next.rises {
            let fraction = now.timeIntervalSince(last.date) / next.date.timeIntervalSince(last.date)
            phase = last.rises ? .day(fraction) : .night(fraction)
            sunrise = last.rises ? last.date : next.date
            sunset = last.rises ? next.date : last.date
        } else {
            let month = Calendar.current.component(.month, from: now)
            let northernSummer = (4...9).contains(month)
            phase = (latitude >= 0) == northernSummer ? .polarDay : .polarNight
            sunrise = nil
            sunset = nil
        }
    }

    var daylight: TimeInterval? {
        guard let sunrise, let sunset, sunset > sunrise else { return nil }
        return sunset.timeIntervalSince(sunrise)
    }
}

/// Horizon, the day's arc, a shallow night arc below it, and the sun riding whichever one it's on.
private struct SunArc: View {
    let phase: SolarDay.Phase

    var body: some View {
        Canvas { context, size in
            let geometry = ArcGeometry(size: size)
            drawGuides(&context, geometry)
            switch phase {
            case .day(let fraction): drawDay(&context, geometry, fraction: fraction)
            case .night(let fraction): drawBody(&context, at: geometry.night(fraction), lit: false)
            case .polarDay: drawDay(&context, geometry, fraction: 0.5)
            case .polarNight: drawBody(&context, at: geometry.night(0.5), lit: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawGuides(_ context: inout GraphicsContext, _ geometry: ArcGeometry) {
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: geometry.horizon))
        horizon.addLine(to: CGPoint(x: geometry.size.width, y: geometry.horizon))
        context.stroke(horizon, with: .color(.white.opacity(0.18)), lineWidth: 1)
        let dashed = StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 4.5])
        context.stroke(geometry.dayPath(to: 1), with: .color(.white.opacity(0.32)), style: dashed)
        context.stroke(geometry.nightPath(), with: .color(.white.opacity(0.14)), style: dashed)
    }

    private func drawDay(_ context: inout GraphicsContext, _ geometry: ArcGeometry, fraction: Double) {
        let point = geometry.day(fraction)
        var spent = geometry.dayPath(to: fraction)
        spent.addLine(to: CGPoint(x: point.x, y: geometry.horizon))
        spent.closeSubpath()
        context.fill(spent, with: .linearGradient(Gradient(colors: [Theme.ember.opacity(0.26), Theme.ember.opacity(0.02)]),
                                                  startPoint: CGPoint(x: 0, y: geometry.top), endPoint: CGPoint(x: 0, y: geometry.horizon)))
        context.stroke(geometry.dayPath(to: fraction),
                       with: .linearGradient(Gradient(colors: [Theme.brass, Theme.ember]),
                                             startPoint: CGPoint(x: geometry.left, y: 0), endPoint: point),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        drawBody(&context, at: point, lit: true)
    }

    private func drawBody(_ context: inout GraphicsContext, at point: CGPoint, lit: Bool) {
        let radius = lit ? 5.0 : 3.5
        if lit {
            let glow = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [Theme.brass.opacity(0.55), .clear]),
                                                                      center: point, startRadius: 0, endRadius: 14))
        }
        let disc = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: lit ? .color(Theme.cream) : .color(Theme.graphiteRaised))
        context.stroke(disc, with: .color(lit ? Theme.brass : .white.opacity(0.35)), lineWidth: lit ? 1.5 : 1)
    }
}

/// Half-ellipse above the horizon for the day, a shallower one below for the night.
private struct ArcGeometry {
    let size: CGSize
    let inset: CGFloat = 8

    var left: CGFloat { inset }
    var width: CGFloat { size.width - inset * 2 }
    var horizon: CGFloat { size.height * 0.8 }
    var top: CGFloat { inset + 2 }
    var height: CGFloat { horizon - top }
    var nightDepth: CGFloat { size.height - horizon - 4 }

    func day(_ t: Double) -> CGPoint {
        CGPoint(x: left + width * (1 - cos(.pi * t)) / 2, y: horizon - height * sin(.pi * t))
    }

    /// Runs from the sunset side back to the sunrise side.
    func night(_ t: Double) -> CGPoint {
        CGPoint(x: left + width * (1 + cos(.pi * t)) / 2, y: horizon + nightDepth * sin(.pi * t))
    }

    func dayPath(to end: Double) -> Path { sampled(day, to: end) }
    func nightPath() -> Path { sampled(night, to: 1) }

    private func sampled(_ point: (Double) -> CGPoint, to end: Double) -> Path {
        let steps = max(2, Int(48 * end))
        var path = Path()
        path.move(to: point(0))
        for step in 1...steps { path.addLine(to: point(end * Double(step) / Double(steps))) }
        return path
    }
}

// MARK: Moon

/// The lit part of the disc: one limb as a half circle, the terminator as a half ellipse.
private nonisolated struct MoonLitShape: Shape {
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let waxing = phase < 0.5
        let side: CGFloat = waxing ? 1 : -1
        let illumination = (1 - cos(2 * .pi * phase)) / 2
        let terminator = radius * CGFloat(abs(cos(2 * .pi * phase)))
        let bulge: CGFloat = illumination < 0.5 ? 1 : -1
        let steps = 32
        var path = Path()
        for step in 0...steps {
            let angle = -Double.pi / 2 + .pi * Double(step) / Double(steps)
            let point = CGPoint(x: center.x + side * radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in 0...steps {
            let angle = Double.pi * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: center.x + side * bulge * terminator * CGFloat(sin(angle)),
                                     y: center.y + radius * CGFloat(cos(angle))))
        }
        path.closeSubpath()
        return path
    }
}

/// A moon with a soft terminator, a few maria and a faint earthshine on the dark side.
private struct MoonDisc: View {
    let phase: MoonPhase
    var flipped = false

    private static let maria: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.36, 0.34, 0.13), (0.58, 0.30, 0.09), (0.62, 0.55, 0.15), (0.40, 0.62, 0.08), (0.30, 0.48, 0.06), (0.70, 0.74, 0.05),
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Color(white: 0.17))
                Circle()
                    .fill(RadialGradient(colors: [Theme.cream, Color(red: 0.86, green: 0.82, blue: 0.74)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: side * 0.7))
                    .mask(MoonLitShape(phase: phase.phase).fill(.white).blur(radius: max(0.6, side * 0.025)))
                ForEach(Self.maria.indices, id: \.self) { index in
                    let spot = Self.maria[index]
                    Circle()
                        .fill(.black.opacity(0.09))
                        .frame(width: side * spot.r * 2, height: side * spot.r * 2)
                        .position(x: side * spot.x, y: side * spot.y)
                }
                Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .scaleEffect(x: flipped ? -1 : 1)
            .shadow(color: Theme.cream.opacity(0.28 * phase.illumination), radius: side * 0.12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
