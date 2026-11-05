import AppKit
import CoreLocation
import ShelfCore
import SwiftUI

/// Which layout a widget should use for the space it was given.
enum InfoTier {
    case small, medium, large

    init(_ size: CGSize) {
        if size.height > 260 { self = .large }
        else if size.width > 260 { self = .medium }
        else { self = .small }
    }
}

// MARK: Sparklines

/// A rolling sample line, right-aligned so new values enter from the trailing edge.
nonisolated struct InfoSparklineShape: Shape {
    var values: [Double]
    var capacity: Int
    var ceiling: Double
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, ceiling > 0 else { return Path() }
        let step = rect.width / CGFloat(max(1, capacity - 1))
        let startX = rect.maxX - step * CGFloat(values.count - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(x: startX + step * CGFloat(index),
                    y: rect.maxY - rect.height * CGFloat(min(1, max(0, value / ceiling))))
        }
        var path = Path()
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1], point = points[index]
            path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
        }
        path.addLine(to: points[points.count - 1])
        if closed {
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            path.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// Area sparkline: a soft fill under a crisp line, on a hairline baseline.
struct InfoSparkline: View {
    let history: SampleHistory
    let color: Color
    var ceiling: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            InfoSparklineShape(values: history.values, capacity: history.capacity, ceiling: ceiling, closed: true)
                .fill(LinearGradient(colors: [color.opacity(0.42), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            InfoSparklineShape(values: history.values, capacity: history.capacity, ceiling: ceiling, closed: false)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    /// Headroom above the recent peak, with a floor so idle noise stays flat.
    static func ceiling(for values: [Double], floor: Double) -> Double {
        max(values.max() ?? 0, floor) * 1.15
    }
}

// MARK: Location

enum InfoLocationAccess {
    enum State { case granted, denied, undetermined }

    private static let manager = CLLocationManager()

    static var state: State {
        switch manager.authorizationStatus {
        case .notDetermined: .undetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// What location-based widgets show before they know where you are.
struct InfoLocationNeeded: View {
    let compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.weather.locationDenied ? .denied : InfoLocationAccess.state
        switch state {
        case .denied:
            WidgetPlaceholder(symbol: "location.slash", title: "Location is off",
                              detail: compact ? "Or set a city in settings" : "Type a city in this widget's settings, or allow Shelf in Privacy settings.",
                              action: ("Open Settings", InfoLocationAccess.openPrivacySettings))
        case .undetermined:
            WidgetPlaceholder(symbol: "location", title: "Where are you?",
                              detail: compact ? "Or set a city in settings" : "Allow location, or type a city in this widget's settings.",
                              action: ("Allow Location", { model.weather.requestLocation() }))
        case .granted:
            WidgetPlaceholder(symbol: "location.magnifyingglass", title: "Finding you")
                .onAppear { model.weather.requestLocation() }
        }
    }
}

/// Open-Meteo geocoding with the place's time zone, which the shared lookup doesn't return.
nonisolated enum InfoGeocoder {
    struct Place: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
        let timeZone: String?
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let timezone: String?
        }
        let results: [Result]?
    }

    static func lookup(_ name: String) async throws -> Place? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "count", value: "1")]
        guard let url = components?.url else { return nil }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let first = try JSONDecoder().decode(Response.self, from: data).results?.first else { return nil }
        return Place(name: first.name, latitude: first.latitude, longitude: first.longitude, timeZone: first.timezone)
    }
}

// MARK: Formatting

enum InfoFormat {
    static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        return hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    /// "12.3 MB/s" split into the number and its unit, so they can be set at different sizes.
    static func rateParts(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let text = ByteRate.format(bytesPerSecond)
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}
