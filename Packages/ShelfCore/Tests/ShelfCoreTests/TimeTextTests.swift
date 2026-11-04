import Foundation
import Testing
@testable import ShelfCore

@Suite struct WordClockTests {
    @Test(arguments: [
        (3, 0, "IT IS THREE O'CLOCK"),
        (3, 2, "IT IS THREE O'CLOCK"),
        (3, 3, "IT IS FIVE PAST THREE"),
        (3, 15, "IT IS QUARTER PAST THREE"),
        (3, 30, "IT IS HALF PAST THREE"),
        (3, 40, "IT IS TWENTY TO FOUR"),
        (3, 45, "IT IS QUARTER TO FOUR"),
        (12, 58, "IT IS ONE O'CLOCK"),
        (0, 0, "IT IS TWELVE O'CLOCK"),
        (23, 35, "IT IS TWENTY-FIVE TO TWELVE"),
    ])
    func `phrases the time in words`(hour: Int, minute: Int, text: String) {
        #expect(WordClock.phrase(hour: hour, minute: minute) == text)
    }

    @Test func `every lit word exists in the letter grid`() {
        for hour in 0..<24 {
            for minute in stride(from: 0, to: 60, by: 5) {
                let lit = WordClock.litCells(hour: hour, minute: minute)
                #expect(!lit.isEmpty)
                #expect(lit.allSatisfy { $0.row < WordClock.grid.count && $0.column < WordClock.grid[0].count })
            }
        }
    }
}

@Suite struct DayProgressTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }

    @Test func `noon is half the day`() {
        let noon = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        #expect(abs(DayProgress.fraction(of: .day, at: noon, calendar: cal) - 0.5) < 0.0001)
    }

    @Test func `start of the year is zero`() {
        let start = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(DayProgress.fraction(of: .year, at: start, calendar: cal) == 0)
        #expect(DayProgress.fraction(of: .month, at: start, calendar: cal) == 0)
    }

    @Test func `countdown splits into days hours minutes`() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let target = now.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
        let parts = Countdown.parts(from: now, to: target)
        #expect(parts.days == 2 && parts.hours == 3 && parts.minutes == 4 && parts.seconds == 5)
        #expect(Countdown.parts(from: target, to: now).isPast)
    }
}

@Suite struct MetersTests {
    @Test func `cpu usage comes from tick deltas`() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 870, nice: 0)
        #expect(abs(CPUTicks.usage(from: a, to: b) - 0.8) < 0.0001)
        #expect(CPUTicks.usage(from: a, to: a) == 0)
    }

    @Test func `rate meter reports bytes per second and survives counter resets`() {
        var meter = RateMeter()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(meter.sample(total: 1_000, at: t0) == nil)
        #expect(meter.sample(total: 3_000, at: t0.addingTimeInterval(2)) == 1_000)
        #expect(meter.sample(total: 10, at: t0.addingTimeInterval(3)) == 0)
    }

    @Test func `history keeps a bounded window`() {
        var history = SampleHistory(capacity: 3)
        for v in [1.0, 2, 3, 4] { history.append(v) }
        #expect(history.values == [2, 3, 4])
    }

    @Test func `battery info reads registry values`() {
        let info = BatteryInfo(registry: [
            "CurrentCapacity": 80, "MaxCapacity": 100, "AppleRawMaxCapacity": 4_500, "DesignCapacity": 5_000,
            "CycleCount": 212, "IsCharging": true, "ExternalConnected": true, "TimeRemaining": 45,
        ])
        #expect(info.level == 0.8)
        #expect(info.health == 0.9)
        #expect(info.cycleCount == 212)
        #expect(info.isCharging)
        #expect(info.minutesRemaining == 45)
    }

    @Test func `byte formatting is compact`() {
        #expect(ByteRate.format(512) == "512 B/s")
        #expect(ByteRate.format(1_536) == "1.5 KB/s")
        #expect(ByteRate.format(12_400_000) == "12.4 MB/s")
    }
}
