import SwiftUI

/// Ticks on whole multiples of `interval` (every second, every minute), so a clock changes exactly
/// when the wall clock does instead of drifting from whenever the view appeared.
nonisolated struct AlignedSchedule: TimelineSchedule {
    let interval: TimeInterval

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let step = max(interval, 0.01)
        let start = (startDate.timeIntervalSinceReferenceDate / step).rounded(.down) * step
        return sequence(first: Date(timeIntervalSinceReferenceDate: start)) { $0.addingTimeInterval(step) }
    }
}

/// Hour, minute and second of a date, with the fraction of the current second kept for sweeping hands.
nonisolated struct ClockReading: Equatable {
    let hour: Int
    let minute: Int
    let second: Int
    let fraction: Double

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
        second = parts.second ?? 0
        fraction = Double(parts.nanosecond ?? 0) / 1_000_000_000
    }

    /// Hour on a 12-hour dial, 1...12.
    var hour12: Int { hour % 12 == 0 ? 12 : hour % 12 }
    var isPM: Bool { hour >= 12 }
    /// Seconds since midnight, fractional.
    var secondsOfDay: Double { Double(hour * 3600 + minute * 60 + second) + fraction }
}

/// Round glass button used by the timer widgets.
struct TimeControlButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 30
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(Theme.textPrimary)
        .glassCircle(tint: tint, interactive: true)
        .accessibilityLabel(label)
    }
}
