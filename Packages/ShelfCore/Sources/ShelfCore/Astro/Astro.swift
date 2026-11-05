import Foundation

/// Sunrise and sunset from the NOAA solar position equations. Offline, accurate to a minute or two.
public struct SunTimes: Sendable, Equatable {
    public let sunrise: Date
    public let sunset: Date
    public let solarNoon: Date

    /// Nil during polar day or polar night.
    public init?(date: Date, latitude: Double, longitude: Double) {
        // Pick the calendar day by local solar time, so evenings in the Americas and mornings in Asia
        // get their own day rather than the UTC one.
        let localDay = (date.timeIntervalSince1970 / 86_400 + longitude / 360).rounded(.down)
        let dayStart = localDay + 2_440_587.5  // Julian day at 00:00 UTC of that day
        let t = (dayStart + 0.5 - 2_451_545.0) / 36_525  // centuries since J2000 at noon UTC

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = meanAnomaly.radians
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(2 * m) * (0.019993 - 0.000101 * t) + sin(3 * m) * 0.000289
        let trueLongitude = meanLongitude + center
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega.radians)
        let obliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60 + 0.00256 * cos(omega.radians)
        let declination = asin(sin(obliquity.radians) * sin(apparentLongitude.radians))

        let y = pow(tan(obliquity.radians / 2), 2)
        let l0 = meanLongitude.radians
        let equationOfTime = 4 * (y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m)).degrees

        let zenith = 90.833.radians
        let cosHourAngle = (cos(zenith) / (cos(latitude.radians) * cos(declination))) - tan(latitude.radians) * tan(declination)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngle = acos(cosHourAngle).degrees

        let noonMinutes = 720 - 4 * longitude - equationOfTime
        let midnight = Date(timeIntervalSince1970: localDay * 86_400)
        solarNoon = midnight.addingTimeInterval(noonMinutes * 60)
        sunrise = midnight.addingTimeInterval((noonMinutes - 4 * hourAngle) * 60)
        sunset = midnight.addingTimeInterval((noonMinutes + 4 * hourAngle) * 60)
    }

    /// 0 at sunrise, 1 at sunset, clamped outside daylight.
    public func dayFraction(at date: Date) -> Double {
        let span = sunset.timeIntervalSince(sunrise)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(sunrise) / span))
    }
}

/// Moon phase as a fraction of the synodic month: 0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter.
public struct MoonPhase: Sendable, Equatable {
    public static let synodicMonth = 29.530588853
    /// A known new moon: 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    public let phase: Double

    public init(phase: Double) {
        let wrapped = phase.truncatingRemainder(dividingBy: 1)
        self.phase = wrapped < 0 ? wrapped + 1 : wrapped
    }

    public init(date: Date) {
        let days = date.timeIntervalSince(Self.referenceNewMoon) / 86_400
        self.init(phase: days / Self.synodicMonth)
    }

    /// Lit fraction of the disc, 0...1.
    public var illumination: Double { (1 - cos(2 * .pi * phase)) / 2 }

    public var isWaxing: Bool { phase < 0.5 }

    public var name: String {
        switch phase {
        case ..<0.0339, 0.9661...: "New Moon"
        case ..<0.216: "Waxing Crescent"
        case ..<0.284: "First Quarter"
        case ..<0.466: "Waxing Gibbous"
        case ..<0.534: "Full Moon"
        case ..<0.716: "Waning Gibbous"
        case ..<0.784: "Last Quarter"
        default: "Waning Crescent"
        }
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
