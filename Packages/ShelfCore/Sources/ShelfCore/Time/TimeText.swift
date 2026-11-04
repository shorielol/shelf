import Foundation

/// Spells the time in five-minute steps and maps the words onto an 11 x 11 letter grid.
public enum WordClock {
    public struct Cell: Hashable, Sendable {
        public let row: Int
        public let column: Int
    }

    public static let grid: [String] = [
        "ITKISQHALFB",
        "QUARTERZTEN",
        "TWENTYXFIVE",
        "PASTJTOVONE",
        "TWOZTHREEPX",
        "FOURFIVESIX",
        "SEVENEIGHTQ",
        "NINEXTENQZK",
        "ELEVENWQKPZ",
        "TWELVEXZQJB",
        "BXOCLOCKZVQ",
    ]

    /// Word key to (row, first column, length).
    static let words: [String: (Int, Int, Int)] = [
        "IT": (0, 0, 2), "IS": (0, 3, 2), "HALF": (0, 6, 4),
        "QUARTER": (1, 0, 7), "TEN_M": (1, 8, 3),
        "TWENTY": (2, 0, 6), "FIVE_M": (2, 7, 4),
        "PAST": (3, 0, 4), "TO": (3, 5, 2),
        "H1": (3, 8, 3), "H2": (4, 0, 3), "H3": (4, 4, 5), "H4": (5, 0, 4), "H5": (5, 4, 4), "H6": (5, 8, 3),
        "H7": (6, 0, 5), "H8": (6, 5, 5), "H9": (7, 0, 4), "H10": (7, 5, 3), "H11": (8, 0, 6), "H12": (9, 0, 6),
        "OCLOCK": (10, 2, 6),
    ]

    static let hourNames = ["TWELVE", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN"]

    public static func phrase(hour: Int, minute: Int) -> String {
        keys(hour: hour, minute: minute).map(spoken).joined(separator: " ").replacingOccurrences(of: "TWENTY FIVE", with: "TWENTY-FIVE")
    }

    public static func litCells(hour: Int, minute: Int) -> Set<Cell> {
        var cells = Set<Cell>()
        for key in keys(hour: hour, minute: minute) {
            guard let (row, start, length) = words[key] else { continue }
            for column in start..<(start + length) { cells.insert(Cell(row: row, column: column)) }
        }
        return cells
    }

    static func keys(hour: Int, minute: Int) -> [String] {
        let rounded = (minute + 2) / 5 * 5
        let isTo = rounded > 30
        let displayHour = ((hour + (isTo || rounded == 60 ? 1 : 0)) % 12 + 12) % 12
        let hourKey = "H\(displayHour == 0 ? 12 : displayHour)"
        let relative: [String]
        switch rounded % 60 {
        case 0: return ["IT", "IS", hourKey, "OCLOCK"]
        case 5, 55: relative = ["FIVE_M"]
        case 10, 50: relative = ["TEN_M"]
        case 15, 45: relative = ["QUARTER"]
        case 20, 40: relative = ["TWENTY"]
        case 25, 35: relative = ["TWENTY", "FIVE_M"]
        default: relative = ["HALF"]
        }
        return ["IT", "IS"] + relative + [isTo ? "TO" : "PAST", hourKey]
    }

    private static func spoken(_ key: String) -> String {
        switch key {
        case "TEN_M": "TEN"
        case "FIVE_M": "FIVE"
        case "OCLOCK": "O'CLOCK"
        case let hour where hour.hasPrefix("H") && Int(hour.dropFirst()) != nil: hourNames[(Int(hour.dropFirst()) ?? 12) % 12]
        default: key
        }
    }
}

public enum DayProgress {
    public enum Span: String, CaseIterable, Sendable {
        case day, week, month, year

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    public static func fraction(of span: Span, at date: Date, calendar: Calendar = .current) -> Double {
        guard let interval = calendar.dateInterval(of: span.component, for: date), interval.duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
    }
}

public enum Countdown {
    public struct Parts: Sendable, Equatable {
        public let days: Int
        public let hours: Int
        public let minutes: Int
        public let seconds: Int
        public let isPast: Bool
    }

    public static func parts(from now: Date, to target: Date) -> Parts {
        let total = Int(target.timeIntervalSince(now).rounded(.down))
        let remaining = max(0, total)
        return Parts(
            days: remaining / 86_400,
            hours: remaining % 86_400 / 3_600,
            minutes: remaining % 3_600 / 60,
            seconds: remaining % 60,
            isPast: total < 0
        )
    }
}
