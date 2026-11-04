import Darwin
import Foundation
import IOKit

/// Cumulative CPU ticks from the kernel.
public struct CPUTicks: Sendable, Equatable {
    public let user: Double
    public let system: Double
    public let idle: Double
    public let nice: Double

    public init(user: Double, system: Double, idle: Double, nice: Double) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public static func usage(from a: CPUTicks, to b: CPUTicks) -> Double {
        let busy = (b.user - a.user) + (b.system - a.system) + (b.nice - a.nice)
        let total = busy + (b.idle - a.idle)
        guard total > 0 else { return 0 }
        return min(1, max(0, busy / total))
    }

    public static func current() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            user: Double(ticks.0), system: Double(ticks.1), idle: Double(ticks.2), nice: Double(ticks.3)
        )
    }
}

public enum MemoryMeter {
    /// Fraction of physical memory in use (active + wired + compressed), like Activity Monitor's "Memory Used".
    public static func usedFraction() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(getpagesize())
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(1, used / total) : nil
    }
}

public enum DiskMeter {
    public static func usedFraction(for url: URL = URL(fileURLWithPath: "/")) -> Double? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return min(1, max(0, 1 - Double(available) / Double(total)))
    }
}

public enum NetworkMeter {
    /// Total bytes in and out across non-loopback interfaces.
    public static func totals() -> (received: Double, sent: Double)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var received = 0.0, sent = 0.0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += Double(data.pointee.ifi_ibytes)
            sent += Double(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }
}

/// Turns a cumulative counter into a per-second rate.
public struct RateMeter: Sendable {
    private var last: (total: Double, date: Date)?

    public init() {}

    public mutating func sample(total: Double, at date: Date) -> Double? {
        defer { last = (total, date) }
        guard let last else { return nil }
        let elapsed = date.timeIntervalSince(last.date)
        guard elapsed > 0, total >= last.total else { return 0 }
        return (total - last.total) / elapsed
    }
}

/// Fixed-size rolling window for sparklines.
public struct SampleHistory: Sendable, Equatable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

public struct BatteryInfo: Sendable, Equatable {
    public let level: Double
    public let health: Double?
    public let cycleCount: Int?
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let minutesRemaining: Int?

    /// Values from the `AppleSmartBattery` IORegistry entry.
    public init(registry: [String: Any]) {
        let current = (registry["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0
        let max = (registry["MaxCapacity"] as? NSNumber)?.doubleValue ?? 100
        level = max > 0 ? min(1, current / max) : 0
        if let raw = (registry["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue,
           let design = (registry["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0 {
            health = min(1, raw / design)
        } else {
            health = nil
        }
        cycleCount = (registry["CycleCount"] as? NSNumber)?.intValue
        isCharging = (registry["IsCharging"] as? Bool) ?? false
        isPluggedIn = (registry["ExternalConnected"] as? Bool) ?? false
        let minutes = (registry["TimeRemaining"] as? NSNumber)?.intValue
        minutesRemaining = minutes.flatMap { $0 > 0 && $0 < 65_535 ? $0 : nil }
    }

    /// Nil on Macs without a battery.
    public static func current() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryInfo(registry: dictionary)
    }
}

public enum ByteRate {
    public static func format(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return unit == 0 ? "\(Int(value)) \(units[0])" : String(format: "%.1f %@", value, units[unit])
    }
}
