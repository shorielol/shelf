import ShelfCore
import SwiftUI

/// Current conditions over a live shader sky, with the next hours and days on larger sizes.
struct WeatherWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @State private var timedOut = false
    @State private var attempt = 0

    private var city: String { context.string("city", "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var fahrenheit: Bool { context.string("unit", "c") == "f" }
    private var tier: InfoTier { InfoTier(context.size) }

    var body: some View {
        content
            .task(id: "\(city)|\(fahrenheit)|\(attempt)") {
                timedOut = false
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { timedOut = true }
            }
    }

    @ViewBuilder private var content: some View {
        if city.isEmpty, model.weather.currentLocation == nil {
            WidgetCard { InfoLocationNeeded(compact: tier == .small) }
        } else if let entry = model.weather.report(for: city, fahrenheit: fahrenheit) {
            WeatherFace(place: entry.place, report: entry.report, isHere: city.isEmpty, tier: tier)
        } else {
            WidgetCard { waiting }
        }
    }

    @ViewBuilder private var waiting: some View {
        if timedOut {
            WidgetPlaceholder(symbol: "cloud.slash", title: "No forecast",
                              detail: city.isEmpty ? "Check your connection." : "Couldn't load \(city). Check the name or your connection.",
                              action: ("Try Again", { attempt += 1 }))
        } else {
            WidgetPlaceholder(symbol: "cloud.sun", title: "Reading the sky")
        }
    }
}

/// The loaded widget: sky, scrim, and the layout for its size.
private struct WeatherFace: View {
    let place: WeatherService.Place
    let report: WeatherReport
    let isHere: Bool
    let tier: InfoTier

    var body: some View {
        let current = report.current
        let clock = PlaceClock(report: report, place: place, isHere: isHere)
        ZStack {
            WeatherSky(condition: current.condition, isDay: current.isDay)
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.02), .black.opacity(0.32)], startPoint: .top, endPoint: .bottom)
            layout(clock: clock)
                .padding(Theme.Space.m)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
        }
        .foregroundStyle(Theme.textPrimary)
        .clipShape(.rect(cornerRadius: Theme.Radius.widget, style: .continuous))
        .glass(cornerRadius: Theme.Radius.widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weather in \(displayName)")
        .accessibilityValue(spokenSummary)
    }

    @ViewBuilder private func layout(clock: PlaceClock) -> some View {
        switch tier {
        case .small:
            summary(temperatureSize: 46)
        case .medium:
            HStack(alignment: .top, spacing: Theme.Space.m) {
                summary(temperatureSize: 46).frame(width: 128, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Spacer(minLength: 0)
                    HourlyStrip(hours: clock.nextHours(6, in: report))
                    Spacer(minLength: 0)
                    credit
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: Theme.Space.m - 4) {
                largeHeader
                HourlyStrip(hours: clock.nextHours(6, in: report))
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.control, style: .continuous))
                DailyList(days: Array(report.daily.prefix(5)), current: report.current.temperature)
                Spacer(minLength: 0)
                HStack { Spacer(); credit }
            }
        }
    }

    private var displayName: String { isHere ? "My Location" : place.name }

    private var today: WeatherReport.Day? { report.daily.first }

    private var placeLabel: some View {
        HStack(spacing: 4) {
            if isHere { Image(systemName: "location.fill").font(.system(size: 9, weight: .semibold)) }
            Text(displayName).font(Theme.Typeface.title(13)).lineLimit(1)
        }
    }

    private func summary(temperatureSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            placeLabel
            Text(InfoFormat.degrees(report.current.temperature))
                .font(Theme.Typeface.numeral(temperatureSize, weight: .medium))
                .contentTransition(.numericText())
                .padding(.leading, -2)
            Spacer(minLength: 0)
            Image(systemName: report.current.condition.symbol(isDay: report.current.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 15, weight: .medium))
                .padding(.bottom, 3)
            Text(report.current.condition.label).font(Theme.Typeface.title(12)).lineLimit(1)
            highLow.font(Theme.Typeface.numeral(11, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var highLow: Text {
        guard let today else { return Text("") }
        return Text("H \(InfoFormat.degrees(today.high))  L \(InfoFormat.degrees(today.low))")
    }

    private var largeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                placeLabel
                Text(InfoFormat.degrees(report.current.temperature))
                    .font(Theme.Typeface.numeral(52, weight: .medium))
                    .padding(.leading, -2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: report.current.condition.symbol(isDay: report.current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 22, weight: .medium))
                    .frame(height: 26)
                Text(report.current.condition.label).font(Theme.Typeface.title(13))
                highLow.font(Theme.Typeface.numeral(11, weight: .medium)).foregroundStyle(Theme.textSecondary)
                Text("Feels like \(InfoFormat.degrees(report.current.feelsLike))")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var credit: some View {
        Text("Open-Meteo")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
    }

    private var spokenSummary: String {
        var parts = [InfoFormat.degrees(report.current.temperature), report.current.condition.label]
        if let today { parts.append("high \(InfoFormat.degrees(today.high)), low \(InfoFormat.degrees(today.low))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: Sky

/// The `weatherSky` shader at 30 fps. Clear daytime skies have nothing moving, so they don't tick.
private struct WeatherSky: View {
    let condition: WeatherCondition
    let isDay: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let index = Double(WeatherCondition.allCases.firstIndex(of: condition) ?? 0)
        let still = reduceMotion || (condition == .clear && isDay)
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { timeline in
            let time = still ? 40 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            GeometryReader { proxy in
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.weatherSky(.float2(proxy.size), .float(time), .float(index), .float(isDay ? 1 : 0)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Hours and days

private struct HourlyStrip: View {
    let hours: [(label: String, hour: WeatherReport.Hour, isDay: Bool)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(hours, id: \.hour.id) { item in
                VStack(spacing: 6) {
                    Text(item.label).font(Theme.Typeface.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Image(systemName: item.hour.condition.symbol(isDay: item.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14, weight: .medium))
                        .frame(height: 18)
                    Text(InfoFormat.degrees(item.hour.temperature)).font(Theme.Typeface.numeral(13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct DailyList: View {
    let days: [WeatherReport.Day]
    let current: Double

    var body: some View {
        let floor = days.map(\.low).min() ?? 0
        let ceiling = days.map(\.high).max() ?? 1
        VStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: Theme.Space.s) {
                    Text(index == 0 ? "Today" : PlaceClock.weekday(day.date))
                        .font(Theme.Typeface.title(12))
                        .frame(width: 42, alignment: .leading)
                    Image(systemName: day.condition.symbol(isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22)
                    Text(InfoFormat.degrees(day.low))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, alignment: .trailing)
                    RangeBar(low: day.low, high: day.high, floor: floor, ceiling: ceiling, marker: index == 0 ? current : nil)
                    Text(InfoFormat.degrees(day.high)).frame(width: 30, alignment: .leading)
                }
                .font(Theme.Typeface.numeral(12, weight: .medium))
            }
        }
    }
}

/// The day's low to high on the week's scale. The colour comes from where on the scale it sits.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let floor: Double
    let ceiling: Double
    let marker: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(ceiling - floor, 1)
            let start = width * (low - floor) / span
            let end = width * (high - floor) / span
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                LinearGradient(colors: [Theme.moss, Theme.brass, Theme.ember], startPoint: .leading, endPoint: .trailing)
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(5, end - start)).offset(x: start)
                    }
                if let marker {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                        .offset(x: min(max(width * (marker - floor) / span, 0), width) - 3.5)
                }
            }
        }
        .frame(height: 5)
    }
}

// MARK: Local time at the place

/// Open-Meteo returns wall-clock times for the place, not its offset. The offset falls out of comparing
/// its local sunrise with the absolute one SunTimes computes.
private struct PlaceClock {
    let offset: TimeInterval

    init(report: WeatherReport, place: WeatherService.Place, isHere: Bool, now: Date = Date()) {
        if isHere {
            offset = TimeInterval(TimeZone.current.secondsFromGMT(for: now))
            return
        }
        let estimate = (place.longitude / 15).rounded() * 3600
        guard let sunrise = report.daily.first.flatMap({ Self.wallClock($0.sunrise) }),
              let sun = SunTimes(date: now, latitude: place.latitude, longitude: place.longitude) else {
            offset = estimate
            return
        }
        var difference = sunrise.timeIntervalSince(sun.sunrise)
        difference -= ((difference - estimate) / 86_400).rounded() * 86_400
        offset = (difference / 900).rounded() * 900
    }

    func nextHours(_ count: Int, in report: WeatherReport, now: Date = Date()) -> [(label: String, hour: WeatherReport.Hour, isDay: Bool)] {
        let key = Self.hourKey.string(from: now.addingTimeInterval(offset))
        let start = report.hourly.firstIndex { $0.time.hasPrefix(key) } ?? 0
        return report.hourly.dropFirst(start).prefix(count).enumerated().map { index, hour in
            let day = report.daily.first { hour.time.hasPrefix($0.date) }
            let isDay = day.map { hour.time >= $0.sunrise && hour.time < $0.sunset } ?? true
            return (index == 0 ? "Now" : Self.hourLabel(hour.time), hour, isDay)
        }
    }

    static func hourLabel(_ wallTime: String) -> String {
        guard let date = wallClock(wallTime) else { return "" }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).hour(.defaultDigits(amPM: .narrow)))
    }

    static func weekday(_ wallDate: String) -> String {
        guard let date = dayFormatter.date(from: wallDate) else { return "" }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
    }

    /// A wall-clock string read as if it were UTC, so its digits survive formatting in GMT.
    static func wallClock(_ text: String) -> Date? { minuteFormatter.date(from: text) }

    private static let minuteFormatter = formatter("yyyy-MM-dd'T'HH:mm")
    private static let dayFormatter = formatter("yyyy-MM-dd")
    private static let hourKey = formatter("yyyy-MM-dd'T'HH")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = format
        return formatter
    }
}
