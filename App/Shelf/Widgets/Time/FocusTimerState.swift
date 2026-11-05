import ShelfCore
import SwiftUI

/// The focus timer's state, read from and written back to widget config.
/// Times are stored as Unix timestamps; 0 means "not set" since config keys can't be removed.
nonisolated struct FocusTimerState: Equatable {
    enum Phase: String { case work, rest }

    static let roundsPerSet = 4

    let isStopwatch: Bool
    let workMinutes: Double
    let breakMinutes: Double
    let phase: Phase
    /// Work rounds finished in this set.
    let round: Int
    /// When the running timer phase ends; nil while paused.
    let endsAt: Date?
    /// Time left in a paused phase; nil means the full length.
    let remaining: TimeInterval?
    let stopwatchStart: Date?
    let stopwatchElapsed: TimeInterval

    init(config: WidgetConfig) {
        isStopwatch = config.string("mode", default: "timer") == "stopwatch"
        workMinutes = max(1, config.double("work", default: 25) ?? 25)
        breakMinutes = max(1, config.double("break", default: 5) ?? 5)
        phase = config.string("phase", default: "work") == Phase.rest.rawValue ? .rest : .work
        round = min(Self.roundsPerSet, max(0, Int(config.double("round", default: 0) ?? 0)))
        let ends = config.double("endsAt", default: 0) ?? 0
        endsAt = !isStopwatch && ends > 0 ? Date(timeIntervalSince1970: ends) : nil
        let paused = config.double("remaining", default: 0) ?? 0
        remaining = paused > 0 ? paused : nil
        let start = config.double("swStart", default: 0) ?? 0
        stopwatchStart = isStopwatch && start > 0 ? Date(timeIntervalSince1970: start) : nil
        stopwatchElapsed = max(0, config.double("swElapsed", default: 0) ?? 0)
    }

    var isRunning: Bool { isStopwatch ? stopwatchStart != nil : endsAt != nil }
    var isLongBreak: Bool { phase == .rest && round >= Self.roundsPerSet }
    var phaseLength: TimeInterval { (phase == .work ? workMinutes : breakMinutes * (isLongBreak ? 3 : 1)) * 60 }

    var phaseTitle: String {
        if isStopwatch { return "Stopwatch" }
        if phase == .work { return "Focus" }
        return isLongBreak ? "Long break" : "Break"
    }

    var tint: Color {
        if isStopwatch { return Theme.brass }
        return phase == .work ? Theme.ember : Theme.moss
    }

    // MARK: Reading

    struct Reading: Equatable {
        let fraction: Double
        let text: String
        let countsUp: Bool
        let spoken: String
    }

    func reading(at now: Date) -> Reading {
        if isStopwatch {
            let elapsed = stopwatchStart.map { max(0, now.timeIntervalSince($0)) } ?? stopwatchElapsed
            let seconds = Int(elapsed)
            // The ring sweeps once a minute, like a stopwatch's seconds hand.
            return Reading(fraction: Double(seconds % 60) / 60, text: Self.format(seconds), countsUp: true, spoken: Self.spoken(seconds) + " elapsed")
        }
        let left = endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? (remaining ?? phaseLength)
        let seconds = Int(left.rounded(.up))
        return Reading(fraction: min(1, left / phaseLength), text: Self.format(seconds), countsUp: false, spoken: Self.spoken(seconds) + " left")
    }

    static func format(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, secs = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private static func spoken(_ seconds: Int) -> String {
        let minutes = seconds / 60, secs = seconds % 60
        return "\(minutes) minutes \(secs) seconds"
    }

    // MARK: Transitions (config changes to write)

    func started(now: Date) -> [String: ConfigValue] {
        if isStopwatch {
            return ["swStart": .number((now.timeIntervalSince1970 - stopwatchElapsed).rounded())]
        }
        // Whole-second end time, so the display ticks exactly on the second.
        let end = (now.timeIntervalSince1970 + (remaining ?? phaseLength)).rounded()
        return ["endsAt": .number(end), "remaining": .number(0)]
    }

    func paused(now: Date) -> [String: ConfigValue] {
        if isStopwatch {
            let elapsed = stopwatchStart.map { now.timeIntervalSince($0) } ?? stopwatchElapsed
            return ["swElapsed": .number(max(0, elapsed)), "swStart": .number(0)]
        }
        let left = endsAt.map { $0.timeIntervalSince(now) } ?? phaseLength
        return ["endsAt": .number(0), "remaining": .number(max(1, left))]
    }

    /// First press resets the current phase; pressing again on a fresh phase starts the set over.
    func reset(now: Date) -> [String: ConfigValue] {
        if isStopwatch { return ["swStart": .number(0), "swElapsed": .number(0)] }
        if isRunning || remaining != nil { return ["endsAt": .number(0), "remaining": .number(0)] }
        return ["endsAt": .number(0), "remaining": .number(0), "phase": .string(Phase.work.rawValue), "round": .number(0)]
    }

    /// Moves to the next phase, stopped and full length. After the long break the set starts over.
    func advanced() -> [String: ConfigValue] {
        let stopped: [String: ConfigValue] = ["endsAt": .number(0), "remaining": .number(0)]
        switch phase {
        case .work:
            return stopped.merging(["phase": .string(Phase.rest.rawValue), "round": .number(Double(min(Self.roundsPerSet, round + 1)))]) { $1 }
        case .rest:
            let nextRound = isLongBreak ? 0 : round
            return stopped.merging(["phase": .string(Phase.work.rawValue), "round": .number(Double(nextRound))]) { $1 }
        }
    }
}
