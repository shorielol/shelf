import Foundation
import os

/// A city the world clock shows: a display name, its zone, and roughly where it is.
nonisolated struct WorldCity: Hashable, Sendable {
    let name: String
    let zone: TimeZone
    /// From the system zone table, for real sunrise and sunset. Nil for zones like UTC.
    let coordinate: (latitude: Double, longitude: Double)?

    static func == (lhs: WorldCity, rhs: WorldCity) -> Bool { lhs.name == rhs.name && lhs.zone == rhs.zone }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(zone)
    }
}

/// Turns what someone typed ("Tokyo", "Asia/Kolkata", "nyc", "UTC") into cities.
nonisolated enum ZoneDirectory {
    private static let logger = Logger(subsystem: "app.shelf", category: "worldclock")

    static func cities(from text: String, limit: Int) -> [WorldCity] {
        let entries = text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<WorldCity>()
        return entries.compactMap(city(for:)).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }

    static func city(for entry: String) -> WorldCity? {
        let key = entry.lowercased()
        if let identifier = aliases[key] ?? byCityName[key], let zone = TimeZone(identifier: identifier) {
            return WorldCity(name: displayName(entry: entry, identifier: identifier), zone: zone, coordinate: coordinates[identifier])
        }
        if let zone = TimeZone(identifier: entry) {
            return WorldCity(name: displayName(entry: entry, identifier: zone.identifier), zone: zone, coordinate: coordinates[zone.identifier])
        }
        if let zone = TimeZone(abbreviation: entry.uppercased()) {
            return WorldCity(name: entry.uppercased(), zone: zone, coordinate: nil)
        }
        logger.debug("Unknown time zone entry: \(entry, privacy: .public)")
        return nil
    }

    /// "America/New_York" -> "New York"; a typed city name keeps the person's own wording.
    private static func displayName(entry: String, identifier: String) -> String {
        if !entry.contains("/") { return entry.count <= 3 ? entry.uppercased() : entry.capitalized }
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Lowercased city part of every known identifier: "new york" -> "America/New_York".
    private static let byCityName: [String: String] = {
        var map: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            map[city.replacingOccurrences(of: "_", with: " ").lowercased()] = identifier
        }
        return map
    }()

    /// Common names that aren't the zone's own city.
    private static let aliases: [String: String] = [
        "nyc": "America/New_York", "new york city": "America/New_York", "boston": "America/New_York", "washington": "America/New_York",
        "miami": "America/New_York", "atlanta": "America/New_York",
        "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "cupertino": "America/Los_Angeles", "portland": "America/Los_Angeles", "austin": "America/Chicago", "dallas": "America/Chicago",
        "houston": "America/Chicago", "montreal": "America/Toronto", "vancouver": "America/Vancouver",
        "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata",
        "beijing": "Asia/Shanghai", "shenzhen": "Asia/Shanghai", "hong kong": "Asia/Hong_Kong", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo",
        "hanoi": "Asia/Ho_Chi_Minh", "saigon": "Asia/Ho_Chi_Minh", "abu dhabi": "Asia/Dubai",
        "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin", "barcelona": "Europe/Madrid", "milan": "Europe/Rome",
        "manchester": "Europe/London", "edinburgh": "Europe/London", "geneva": "Europe/Zurich",
        "melbourne": "Australia/Melbourne", "canberra": "Australia/Sydney", "wellington": "Pacific/Auckland",
        "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo", "cape town": "Africa/Johannesburg",
    ]

    /// Zone coordinates from the system's zone.tab, read once.
    private static let coordinates: [String: (latitude: Double, longitude: Double)] = {
        guard let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else {
            logger.notice("zone.tab unavailable; world clock will estimate daylight")
            return [:]
        }
        var map: [String: (latitude: Double, longitude: Double)] = [:]
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, let coordinate = parseISO6709(String(columns[1])) else { continue }
            map[String(columns[2])] = coordinate
        }
        return map
    }()

    /// "+353916+1394441" -> (35.65, 139.74). Degrees-minutes with optional seconds.
    static func parseISO6709(_ text: String) -> (latitude: Double, longitude: Double)? {
        guard let split = text.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        let latitude = String(text[text.startIndex..<split])
        let longitude = String(text[split...])
        guard let lat = degrees(latitude, degreeDigits: 2), let lon = degrees(longitude, degreeDigits: 3) else { return nil }
        return (lat, lon)
    }

    private static func degrees(_ text: String, degreeDigits: Int) -> Double? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(text.dropFirst())
        guard digits.count >= degreeDigits + 2, digits.allSatisfy(\.isNumber) else { return nil }
        let number = { (range: Range<Int>) in Double(String(digits[range])) ?? 0 }
        var value = number(0..<degreeDigits) + number(degreeDigits..<(degreeDigits + 2)) / 60
        if digits.count >= degreeDigits + 4 { value += number((degreeDigits + 2)..<(degreeDigits + 4)) / 3600 }
        return sign == "-" ? -value : value
    }
}
