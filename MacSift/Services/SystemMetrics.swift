import Foundation
import Darwin

/// Point-in-time snapshot of system resource usage. All fields are in
/// consistent units so the UI never has to do conversions inline.
struct SystemMetrics: Sendable, Equatable {
    /// Boot volume total / free bytes.
    let diskTotal: Int64
    let diskFree: Int64
    /// Physical RAM — total + currently in use. `used` includes everything
    /// that isn't free, inactive, or purgeable, which matches what Activity
    /// Monitor reports as "Memory Used".
    let memoryTotal: Int64
    let memoryUsed: Int64
    /// Overall CPU load 0.0–1.0, averaged across all cores. Requires at
    /// least two samples to be non-zero — the first call returns 0.
    let cpuLoad: Double
    /// Thermal state, translated from ProcessInfo.
    let thermalState: ProcessInfo.ThermalState

    var diskUsed: Int64 { diskTotal - diskFree }
    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0
    }
    var memoryUsedFraction: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }

    static let zero = SystemMetrics(
        diskTotal: 0, diskFree: 0,
        memoryTotal: 0, memoryUsed: 0,
        cpuLoad: 0,
        thermalState: .nominal
    )
}

/// Reads live system metrics. Stateful because CPU load is computed from
/// the delta between two successive samples — a fresh reader starts at
/// 0% and needs at least one prior call to produce meaningful numbers.
///
/// This type is a reference type (`final class`) rather than a struct
/// because the CPU sampler keeps mutable state across calls. Wrapped in
/// `@unchecked Sendable` — all mutation happens on the same serial
/// dispatch queue owned by the caller (the menu bar view model), so the
/// internal state is never touched concurrently in practice.
final class SystemMetricsReader: @unchecked Sendable {
    private var previousCPUTotal: UInt32 = 0
    private var previousCPUIdle: UInt32 = 0
    private var hasPreviousSample = false

    /// Capture a new snapshot. Safe to call from any thread but the
    /// caller is responsible for not racing itself — typically called
    /// from a single Task-loop in the menu bar view model.
    func snapshot() -> SystemMetrics {
        SystemMetrics(
            diskTotal: diskTotal(),
            diskFree: diskFree(),
            memoryTotal: memoryTotal(),
            memoryUsed: memoryUsed(),
            cpuLoad: sampleCPU(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    // MARK: - Disk

    private func bootVolumeURL() -> URL {
        URL(filePath: "/")
    }

    private func diskTotal() -> Int64 {
        guard let values = try? bootVolumeURL().resourceValues(forKeys: [.volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity else { return 0 }
        return Int64(total)
    }

    private func diskFree() -> Int64 {
        // `volumeAvailableCapacityForImportantUsageKey` is what Finder
        // reports — it accounts for purgeable space macOS can reclaim
        // under pressure. Matches user expectations better than the raw
        // free-bytes number.
        guard let values = try? bootVolumeURL().resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]) else { return 0 }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let raw = values.volumeAvailableCapacity {
            return Int64(raw)
        }
        return 0
    }

    // MARK: - Memory

    private func memoryTotal() -> Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    private func memoryUsed() -> Int64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // `vm_kernel_page_size` is a global C var Swift flags as
        // concurrency-unsafe. `sysconf(_SC_PAGESIZE)` returns the same
        // value and is safe to call from any thread.
        let pageSize = Int64(sysconf(_SC_PAGESIZE))
        // "Used" in Activity Monitor terms ≈ total - free - inactive - purgeable.
        let free = Int64(stats.free_count) * pageSize
        let inactive = Int64(stats.inactive_count) * pageSize
        let purgeable = Int64(stats.purgeable_count) * pageSize
        return max(0, memoryTotal() - free - inactive - purgeable)
    }

    // MARK: - CPU

    /// Sample aggregated CPU load via `host_statistics(HOST_CPU_LOAD_INFO)`.
    /// Returns a 0.0–1.0 fraction averaged across user+system+nice vs
    /// total ticks, computed from the delta since the previous sample.
    /// First call always returns 0.
    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3
        let total = user &+ system &+ idle &+ nice

        defer {
            previousCPUTotal = total
            previousCPUIdle = idle
            hasPreviousSample = true
        }

        guard hasPreviousSample else { return 0 }
        let totalDelta = total &- previousCPUTotal
        let idleDelta = idle &- previousCPUIdle
        guard totalDelta > 0 else { return 0 }
        let busy = Double(totalDelta &- idleDelta) / Double(totalDelta)
        return min(max(busy, 0), 1)
    }
}
