import Testing
import Foundation
@testable import MacSift

@Suite("SystemMetrics · live sampling")
struct SystemMetricsTests {
    @Test func snapshotReturnsPositiveDiskTotal() {
        let reader = SystemMetricsReader()
        let snap = reader.snapshot()
        #expect(snap.diskTotal > 0, "Boot volume should always report a total capacity")
        #expect(snap.diskFree >= 0)
        #expect(snap.diskFree <= snap.diskTotal)
    }

    @Test func snapshotReturnsPositiveMemoryTotal() {
        let reader = SystemMetricsReader()
        let snap = reader.snapshot()
        #expect(snap.memoryTotal > 0, "Physical memory should always be reported")
        #expect(snap.memoryUsed >= 0)
        #expect(snap.memoryUsed <= snap.memoryTotal)
    }

    @Test func cpuLoadStartsAtZeroOnFirstCall() {
        let reader = SystemMetricsReader()
        let first = reader.snapshot()
        // Delta-based sampler needs a prior reading — first call returns 0.
        #expect(first.cpuLoad == 0)
    }

    @Test func cpuLoadIsBetweenZeroAndOneAfterSecondSample() async throws {
        let reader = SystemMetricsReader()
        _ = reader.snapshot()
        // Give the CPU a moment to accumulate ticks — otherwise the delta
        // might be so small we get a zero.
        try await Task.sleep(nanoseconds: 100_000_000)
        let second = reader.snapshot()
        #expect(second.cpuLoad >= 0)
        #expect(second.cpuLoad <= 1)
    }

    @Test func diskUsedFractionIsBoundedZeroToOne() {
        let reader = SystemMetricsReader()
        let snap = reader.snapshot()
        #expect(snap.diskUsedFraction >= 0)
        #expect(snap.diskUsedFraction <= 1)
    }

    @Test func memoryUsedFractionIsBoundedZeroToOne() {
        let reader = SystemMetricsReader()
        let snap = reader.snapshot()
        #expect(snap.memoryUsedFraction >= 0)
        #expect(snap.memoryUsedFraction <= 1)
    }

    @Test func zeroMetricsHasZeroFractions() {
        let zero = SystemMetrics.zero
        #expect(zero.diskUsedFraction == 0)
        #expect(zero.memoryUsedFraction == 0)
        #expect(zero.cpuLoad == 0)
        #expect(zero.diskUsed == 0)
    }

    @Test func snapshotIsEquatableByValue() {
        let a = SystemMetrics(
            diskTotal: 1000, diskFree: 500,
            memoryTotal: 2000, memoryUsed: 1000,
            cpuLoad: 0.42,
            thermalState: .nominal
        )
        let b = SystemMetrics(
            diskTotal: 1000, diskFree: 500,
            memoryTotal: 2000, memoryUsed: 1000,
            cpuLoad: 0.42,
            thermalState: .nominal
        )
        #expect(a == b)
    }
}
