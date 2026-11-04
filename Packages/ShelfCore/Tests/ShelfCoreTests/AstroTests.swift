import Foundation
import Testing
@testable import ShelfCore

@Suite struct AstroTests {
    func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    @Test func `london midsummer sunrise and sunset are close to the almanac`() throws {
        let times = try #require(SunTimes(date: utc(2024, 6, 21), latitude: 51.5074, longitude: -0.1278))
        // Almanac: sunrise 03:43 UTC, sunset 20:21 UTC.
        #expect(abs(times.sunrise.timeIntervalSince(utc(2024, 6, 21, 3, 43))) < 180)
        #expect(abs(times.sunset.timeIntervalSince(utc(2024, 6, 21, 20, 21))) < 180)
    }

    @Test func `polar night has no sunrise`() {
        #expect(SunTimes(date: utc(2024, 12, 21), latitude: 78.2, longitude: 15.6) == nil)
    }

    @Test func `day fraction runs from sunrise to sunset`() throws {
        let times = try #require(SunTimes(date: utc(2024, 3, 20), latitude: 0, longitude: 0))
        let noon = times.sunrise.addingTimeInterval(times.sunset.timeIntervalSince(times.sunrise) / 2)
        #expect(abs(times.dayFraction(at: noon) - 0.5) < 0.001)
        #expect(times.dayFraction(at: times.sunrise.addingTimeInterval(-60)) == 0)
    }

    @Test(arguments: [
        (2024, 4, 8, 18, 0.0),    // new moon (total eclipse)
        (2024, 4, 23, 23, 0.5),   // full moon
        (2024, 4, 15, 19, 0.25),  // first quarter
    ])
    func `moon phase matches known dates`(y: Int, m: Int, d: Int, h: Int, phase: Double) {
        let moon = MoonPhase(date: utc(y, m, d, h))
        let diff = abs(moon.phase - phase)
        #expect(min(diff, 1 - diff) < 0.02)
    }

    @Test func `illumination is zero at new moon and one at full`() {
        #expect(MoonPhase(phase: 0).illumination < 0.001)
        #expect(MoonPhase(phase: 0.5).illumination > 0.999)
        #expect(MoonPhase(phase: 0.25).name == "First Quarter")
        #expect(MoonPhase(phase: 0.02).name == "New Moon")
    }
}
