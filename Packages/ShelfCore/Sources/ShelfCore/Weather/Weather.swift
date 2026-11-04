import Foundation

public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunderstorm

    /// WMO weather interpretation codes, as used by Open-Meteo.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunderstorm
        default: self = .cloudy
        }
    }

    public var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly Cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .snow: "Snow"
        case .thunderstorm: "Thunderstorm"
        }
    }

    public func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }
}

public struct WeatherReport: Sendable, Equatable {
    public struct Current: Sendable, Equatable {
        public let temperature: Double
        public let feelsLike: Double
        public let condition: WeatherCondition
        public let isDay: Bool
        public let windSpeed: Double
        public let humidity: Double
    }

    public struct Hour: Sendable, Equatable, Identifiable {
        public var id: String { time }
        public let time: String
        public let temperature: Double
        public let condition: WeatherCondition
        public let precipitationChance: Int
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public var id: String { date }
        public let date: String
        public let condition: WeatherCondition
        public let high: Double
        public let low: Double
        public let sunrise: String
        public let sunset: String
    }

    public let current: Current
    public let hourly: [Hour]
    public let daily: [Day]
}

/// Open-Meteo forecast API (free, no key; data CC BY 4.0, credited in the app).
public enum OpenMeteoClient {
    public static func forecastURL(latitude: Double, longitude: Double, fahrenheit: Bool) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if fahrenheit { items.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit")) }
        components.queryItems = items
        return components.url!
    }

    public static func fetch(latitude: Double, longitude: Double, fahrenheit: Bool) async throws -> WeatherReport {
        let (data, _) = try await URLSession.shared.data(from: forecastURL(latitude: latitude, longitude: longitude, fahrenheit: fahrenheit))
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let current = WeatherReport.Current(
            temperature: raw.current.temperature_2m,
            feelsLike: raw.current.apparent_temperature,
            condition: WeatherCondition(wmoCode: raw.current.weather_code),
            isDay: raw.current.is_day == 1,
            windSpeed: raw.current.wind_speed_10m ?? 0,
            humidity: raw.current.relative_humidity_2m ?? 0
        )
        let hourly = raw.hourly.time.indices.map { i in
            WeatherReport.Hour(
                time: raw.hourly.time[i],
                temperature: raw.hourly.temperature_2m[i],
                condition: WeatherCondition(wmoCode: raw.hourly.weather_code[i]),
                precipitationChance: raw.hourly.precipitation_probability?[safe: i] ?? 0
            )
        }
        let daily = raw.daily.time.indices.map { i in
            WeatherReport.Day(
                date: raw.daily.time[i],
                condition: WeatherCondition(wmoCode: raw.daily.weather_code[i]),
                high: raw.daily.temperature_2m_max[i],
                low: raw.daily.temperature_2m_min[i],
                sunrise: raw.daily.sunrise?[safe: i] ?? "",
                sunset: raw.daily.sunset?[safe: i] ?? ""
            )
        }
        return WeatherReport(current: current, hourly: hourly, daily: daily)
    }

    // Field names mirror the API's snake_case JSON.
    private struct Raw: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double?
            let relative_humidity_2m: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let precipitation_probability: [Int]?
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]?
            let sunset: [String]?
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
