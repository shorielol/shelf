import Foundation
import Testing
@testable import ShelfCore

@Suite struct WeatherTests {
    func data() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "open-meteo", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func `decodes current, hourly and daily forecasts`() throws {
        let report = try OpenMeteoClient.decode(try data())
        #expect(report.current.temperature == 11.4)
        #expect(report.current.feelsLike == 9.1)
        #expect(report.current.condition == .rain)
        #expect(report.current.isDay)
        #expect(report.hourly.count == 3)
        #expect(report.hourly[2].condition == .clear)
        #expect(report.hourly[0].precipitationChance == 70)
        #expect(report.daily.count == 2)
        #expect(report.daily[0].high == 12.1)
        #expect(report.daily[1].condition == .partlyCloudy)
    }

    @Test(arguments: [
        (0, WeatherCondition.clear), (1, .partlyCloudy), (3, .cloudy), (45, .fog),
        (53, .drizzle), (63, .rain), (73, .snow), (82, .rain), (86, .snow), (95, .thunderstorm), (999, .cloudy),
    ])
    func `maps WMO codes to conditions`(code: Int, condition: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == condition)
    }

    @Test func `forecast URL asks for the fields the widget uses`() throws {
        let url = OpenMeteoClient.forecastURL(latitude: 51.5, longitude: -0.12, fahrenheit: false)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let dict = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        #expect(dict["latitude"] == "51.5")
        #expect(dict["current"]?.contains("weather_code") == true)
        #expect(dict["timezone"] == "auto")
        #expect(dict["temperature_unit"] == nil)
        let f = OpenMeteoClient.forecastURL(latitude: 1, longitude: 2, fahrenheit: true)
        #expect(f.absoluteString.contains("temperature_unit=fahrenheit"))
    }
}
