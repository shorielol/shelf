import Foundation
import Observation
import ShelfCore

/// Samples CPU, memory, disk, network and battery every two seconds, only while a widget is watching.
@Observable
final class SystemStats {
    private(set) var cpu = SampleHistory(capacity: 40)
    private(set) var memory = SampleHistory(capacity: 40)
    private(set) var download = SampleHistory(capacity: 40)
    private(set) var upload = SampleHistory(capacity: 40)
    private(set) var disk: Double = 0
    private(set) var battery: BatteryInfo?

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastTicks: CPUTicks?
    @ObservationIgnored private var inMeter = RateMeter()
    @ObservationIgnored private var outMeter = RateMeter()

    static let interval: Duration = .seconds(2)

    func watch() {
        watchers += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 {
            task?.cancel()
            task = nil
        }
    }

    private func sample() {
        let now = Date()
        if let ticks = CPUTicks.current() {
            if let lastTicks { cpu.append(CPUTicks.usage(from: lastTicks, to: ticks)) }
            lastTicks = ticks
        }
        if let used = MemoryMeter.usedFraction() { memory.append(used) }
        if let totals = NetworkMeter.totals() {
            if let rate = inMeter.sample(total: totals.received, at: now) { download.append(rate) }
            if let rate = outMeter.sample(total: totals.sent, at: now) { upload.append(rate) }
        }
        disk = DiskMeter.usedFraction() ?? disk
        battery = BatteryInfo.current()
    }
}
