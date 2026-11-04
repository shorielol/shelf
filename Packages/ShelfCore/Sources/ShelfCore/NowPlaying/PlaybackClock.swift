import Foundation

/// Playback position anchored to a wall-clock instant, extrapolated between player polls
/// so spinning platters and karaoke wipes stay smooth.
public struct PlaybackClock: Sendable, Equatable {
    public var position: TimeInterval
    public var anchor: Date
    public var isPlaying: Bool
    public var duration: TimeInterval?

    /// Polls disagreeing by less than this are treated as jitter, not a seek.
    public static let driftTolerance: TimeInterval = 0.35

    public init(position: TimeInterval, anchor: Date, isPlaying: Bool, duration: TimeInterval?) {
        self.position = position
        self.anchor = anchor
        self.isPlaying = isPlaying
        self.duration = duration
    }

    public static let stopped = PlaybackClock(position: 0, anchor: .distantPast, isPlaying: false, duration: nil)

    public func position(at date: Date) -> TimeInterval {
        let raw = isPlaying ? position + date.timeIntervalSince(anchor) : position
        let upper = duration ?? .greatestFiniteMagnitude
        return min(max(0, raw), upper)
    }

    public func progress(at date: Date) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return position(at: date) / duration
    }

    /// Rotation of a record platter in degrees. Derived from position so it's identical across widgets.
    public func platterDegrees(at date: Date, rpm: Double) -> Double {
        (position(at: date) * rpm / 60 * 360).truncatingRemainder(dividingBy: 360)
    }

    public func reconciled(reported: TimeInterval, at date: Date, isPlaying playing: Bool, duration newDuration: TimeInterval?) -> PlaybackClock {
        let predicted = position(at: date)
        if playing == isPlaying, newDuration == duration, abs(predicted - reported) < Self.driftTolerance {
            return self
        }
        return PlaybackClock(position: reported, anchor: date, isPlaying: playing, duration: newDuration)
    }
}
