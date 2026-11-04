import Foundation
import Testing
@testable import ShelfCore

/// Smoke tests against the real kernel counters; they only check the readings are sane.
@Suite struct LiveMetersTests {
    @Test func `cpu ticks are readable and monotonic`() throws {
        let a = try #require(CPUTicks.current())
        let b = try #require(CPUTicks.current())
        #expect(b.idle >= a.idle)
        #expect((0...1).contains(CPUTicks.usage(from: a, to: b)))
    }

    @Test func `memory and disk fractions are in range`() throws {
        #expect((0...1).contains(try #require(MemoryMeter.usedFraction())))
        #expect((0...1).contains(try #require(DiskMeter.usedFraction())))
    }

    @Test func `network totals are non-negative`() throws {
        let totals = try #require(NetworkMeter.totals())
        #expect(totals.received >= 0 && totals.sent >= 0)
    }

    @Test func `battery reading is optional but sane`() {
        if let battery = BatteryInfo.current() {
            #expect((0...1).contains(battery.level))
        }
    }
}
