import Foundation

/// Capacity of the device's data volume.
struct DeviceStorage {
    let total: Int64
    let free: Int64
    var used: Int64 { max(total - free, 0) }
    var usedFraction: Double { total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0 }
    var isLow: Bool { total > 0 && Double(free) / Double(total) < 0.10 }

    static func current() -> DeviceStorage {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DeviceStorage(total: Int64(values?.volumeTotalCapacity ?? 0),
                             free: values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
