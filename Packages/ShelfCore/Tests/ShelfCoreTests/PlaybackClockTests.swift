import Foundation
import Testing
@testable import ShelfCore

@Suite struct PlaybackClockTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func `extrapolates while playing`() {
        let clock = PlaybackClock(position: 10, anchor: t0, isPlaying: true, duration: 200)
        #expect(clock.position(at: t0.addingTimeInterval(2.5)) == 12.5)
    }

    @Test func `holds still while paused`() {
        let clock = PlaybackClock(position: 10, anchor: t0, isPlaying: false, duration: 200)
        #expect(clock.position(at: t0.addingTimeInterval(30)) == 10)
    }

    @Test func `clamps to the duration`() {
        let clock = PlaybackClock(position: 199, anchor: t0, isPlaying: true, duration: 200)
        #expect(clock.position(at: t0.addingTimeInterval(10)) == 200)
    }

    @Test func `small drift keeps the smooth clock`() {
        let clock = PlaybackClock(position: 10, anchor: t0, isPlaying: true, duration: 200)
        let now = t0.addingTimeInterval(1)
        let next = clock.reconciled(reported: 11.2, at: now, isPlaying: true, duration: 200)
        #expect(next == clock)
    }

    @Test func `a seek resets the clock`() {
        let clock = PlaybackClock(position: 10, anchor: t0, isPlaying: true, duration: 200)
        let now = t0.addingTimeInterval(1)
        let next = clock.reconciled(reported: 90, at: now, isPlaying: true, duration: 200)
        #expect(next.position(at: now) == 90)
    }

    @Test func `pausing freezes at the reported position`() {
        let clock = PlaybackClock(position: 10, anchor: t0, isPlaying: true, duration: 200)
        let now = t0.addingTimeInterval(1)
        let next = clock.reconciled(reported: 11.05, at: now, isPlaying: false, duration: 200)
        #expect(!next.isPlaying)
        #expect(next.position(at: now.addingTimeInterval(5)) == 11.05)
    }

    @Test func `progress is a fraction of the duration`() {
        let clock = PlaybackClock(position: 50, anchor: t0, isPlaying: false, duration: 200)
        #expect(clock.progress(at: t0) == 0.25)
        let unknown = PlaybackClock(position: 50, anchor: t0, isPlaying: false, duration: nil)
        #expect(unknown.progress(at: t0) == 0)
    }

    @Test func `platter angle follows playback at the chosen rpm`() {
        let clock = PlaybackClock(position: 0, anchor: t0, isPlaying: true, duration: 600)
        // 33 1/3 rpm: 1.8 seconds per revolution.
        #expect(abs(clock.platterDegrees(at: t0.addingTimeInterval(0.9), rpm: 100.0 / 3.0) - 180) < 0.001)
    }
}
