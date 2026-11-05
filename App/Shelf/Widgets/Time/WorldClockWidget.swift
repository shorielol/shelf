import ShelfCore
import SwiftUI

/// Up to four cities, each with a 24-hour sun dial: noon at the top, midnight at the bottom,
/// daylight drawn from that city's real sunrise to sunset.
struct WorldClockWidget: View {
    let context: WidgetContext

    static let defaultZones = "America/New_York, Europe/London, Asia/Tokyo"

    private var cities: [WorldCity] {
        ZoneDirectory.cities(from: context.string("zones", Self.defaultZones), limit: context.size.height < 200 && !context.isWide ? 2 : 4)
    }

    var body: some View {
        let cities = cities
        WidgetCard(padding: context.unit < 200 ? 12 : Theme.Space.m) {
            if cities.isEmpty {
                WidgetPlaceholder(symbol: "globe", title: "Add a city", detail: "Type cities or time zones in settings.")
            } else {
                TimelineView(AlignedSchedule(interval: 60)) { timeline in
                    layout(cities.map { CityTime(city: $0, date: timeline.date) })
                }
            }
        }
    }

    @ViewBuilder
    private func layout(_ times: [CityTime]) -> some View {
        if context.isWide {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                ForEach(times, id: \.city) { column($0) }
            }
            .frame(maxHeight: .infinity)
        } else {
            let large = context.size.height >= 300
            VStack(spacing: 0) {
                ForEach(Array(times.enumerated()), id: \.element.city) { index, time in
                    if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    row(time, large: large).frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func column(_ time: CityTime) -> some View {
        VStack(spacing: 6) {
            SunDial(time: time).frame(width: 46, height: 46)
            Text(time.city.name)
                .font(Theme.Typeface.title(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            clock(time, size: 21)
            Eyebrow(text: time.offsetLabel, color: Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.spoken)
    }

    private func row(_ time: CityTime, large: Bool) -> some View {
        HStack(spacing: large ? Theme.Space.m : 10) {
            SunDial(time: time).frame(width: large ? 52 : 32, height: large ? 52 : 32)
            if large {
                VStack(alignment: .leading, spacing: 2) {
                    Text(time.city.name).font(Theme.Typeface.display(17)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Eyebrow(text: [time.offsetLabel, time.dayLabel].compactMap { $0 }.joined(separator: " · "), color: Theme.textTertiary)
                }
                Spacer(minLength: Theme.Space.s)
                clock(time, size: 32)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(time.city.name).font(Theme.Typeface.title(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(time.offsetLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    }
                    clock(time, size: 24)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(time.spoken)
    }

    private func clock(_ time: CityTime, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(time.clockText)
                .font(Theme.Typeface.numeral(size))
                .foregroundStyle(Theme.textPrimary)
            if let meridiem = time.meridiem {
                Text(meridiem).font(.system(size: max(8, size * 0.36), weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Model

/// A city's time at one moment, already formatted.
private struct CityTime {
    let city: WorldCity
    let reading: ClockReading
    let offsetSeconds: Int
    let dayDifference: Int
    let daylight: (rise: Double, set: Double)

    private static let uses12Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false

    init(city: WorldCity, date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.zone
        self.city = city
        reading = ClockReading(date, calendar: calendar)
        offsetSeconds = city.zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        let localDay = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        dayDifference = (calendar.ordinality(of: .day, in: .era, for: date) ?? 0) - localDay
        daylight = Self.daylight(city: city, date: date, calendar: calendar)
    }

    /// Sunrise and sunset as fractions of the city's day. Falls back to 6:00-18:00 without coordinates.
    private static func daylight(city: WorldCity, date: Date, calendar: Calendar) -> (rise: Double, set: Double) {
        guard let coordinate = city.coordinate,
              let sun = SunTimes(date: date, latitude: coordinate.latitude, longitude: coordinate.longitude) else { return (0.25, 0.75) }
        let rise = ClockReading(sun.sunrise, calendar: calendar).secondsOfDay / 86_400
        let set = ClockReading(sun.sunset, calendar: calendar).secondsOfDay / 86_400
        return rise < set ? (rise, set) : (0.25, 0.75)
    }

    var dayFraction: Double { reading.secondsOfDay / 86_400 }
    var isDaytime: Bool { dayFraction >= daylight.rise && dayFraction < daylight.set }

    var clockText: String {
        Self.uses12Hour ? "\(reading.hour12):" + String(format: "%02d", reading.minute) : String(format: "%02d:%02d", reading.hour, reading.minute)
    }

    var meridiem: String? { Self.uses12Hour ? (reading.isPM ? "PM" : "AM") : nil }

    var offsetLabel: String {
        guard offsetSeconds != 0 else { return "Local" }
        let sign = offsetSeconds > 0 ? "+" : "−"
        let hours = abs(offsetSeconds) / 3600
        let minutes = abs(offsetSeconds) % 3600 / 60
        return minutes == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    var dayLabel: String? {
        switch dayDifference {
        case 1...: "Tomorrow"
        case ..<0: "Yesterday"
        default: nil
        }
    }

    var spoken: String {
        let offset = offsetSeconds == 0 ? "same as local time" : offsetLabel.replacingOccurrences(of: "−", with: "minus ").replacingOccurrences(of: "h", with: " hours")
        return "\(city.name), \(clockText) \(meridiem ?? ""), \(offset), \(isDaytime ? "daytime" : "night")"
    }
}

// MARK: - Sun dial

/// A 24-hour ring: daylight warm, night dark, with twilight in between and the sun riding the ring.
private struct SunDial: View {
    let time: CityTime

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let line = max(2.5, side * 0.09)
            let ringRadius = (side - line) / 2
            ZStack {
                Circle()
                    .fill(time.isDaytime ? Theme.brass.opacity(0.14) : Color.black.opacity(0.28))
                    .padding(line)
                Circle()
                    .strokeBorder(AngularGradient(stops: stops, center: .center, startAngle: .degrees(90), endAngle: .degrees(450)), lineWidth: line)
                horizon(side: side, line: line)
                sun(radius: ringRadius, size: line * 1.55, side: side)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private var stops: [Gradient.Stop] {
        let night = Color(red: 0.16, green: 0.17, blue: 0.24)
        let dusk = Theme.ember.opacity(0.9)
        let day = Theme.brass
        let rise = time.daylight.rise, set = time.daylight.set
        let twilight = 0.025
        return [
            .init(color: night, location: 0),
            .init(color: night, location: max(0, rise - twilight)),
            .init(color: dusk, location: rise),
            .init(color: day, location: min(set, rise + twilight * 2)),
            .init(color: day, location: max(rise, set - twilight * 2)),
            .init(color: dusk, location: set),
            .init(color: night, location: min(1, set + twilight)),
            .init(color: night, location: 1),
        ]
    }

    /// A faint line across the dial at the city's sunrise and sunset.
    private func horizon(side: CGFloat, line: CGFloat) -> some View {
        Path { path in
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side / 2 - line
            path.move(to: point(center: center, fraction: time.daylight.rise, radius: radius))
            path.addLine(to: point(center: center, fraction: time.daylight.set, radius: radius))
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }

    private func sun(radius: CGFloat, size: CGFloat, side: CGFloat) -> some View {
        let position = point(center: CGPoint(x: side / 2, y: side / 2), fraction: time.dayFraction, radius: radius)
        return Circle()
            .fill(time.isDaytime ? Theme.cream : Color(white: 0.8))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: time.isDaytime ? Theme.brass.opacity(0.9) : .clear, radius: size * 0.6)
            .position(position)
    }

    /// Midnight at the bottom, noon at the top, clockwise.
    private func point(center: CGPoint, fraction: Double, radius: CGFloat) -> CGPoint {
        let radians = (180 + fraction * 360) * .pi / 180
        return CGPoint(x: center.x + sin(radians) * radius, y: center.y - cos(radians) * radius)
    }
}
