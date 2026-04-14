import Testing
import Foundation
@testable import MacSift

/// Lightweight perf smoke test. Scans a temp tree containing ~2000 small
/// files and asserts the scan finishes under a generous budget. It's NOT
/// a precise benchmark — the goal is to catch order-of-magnitude
/// regressions (e.g., accidentally removing the delta throttle, re-sorting
/// inside the hot loop, etc.) without flaking on shared CI.
///
/// Budgets are intentionally loose: if the real cost creeps up from
/// ~100ms toward the seconds range, the test still fails.
@Suite("Scan Performance")
struct ScanPerformanceTests {
    private func buildLargeTree(fileCount: Int) throws -> (url: URL, marker: String) {
        let marker = "MacSiftPerf-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(path: marker)
        let fm = FileManager.default

        let cacheDir = root.appending(path: "Library/Caches/com.perf.app")
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Spread files across a few subfolders so the enumerator exercises
        // directory recursion, not just a flat listing.
        let bucketCount = 8
        for bucket in 0..<bucketCount {
            let bucketDir = cacheDir.appending(path: "bucket-\(bucket)")
            try fm.createDirectory(at: bucketDir, withIntermediateDirectories: true)
        }
        let payload = Data(repeating: 0xDE, count: 512)
        for index in 0..<fileCount {
            let bucket = index % bucketCount
            let url = cacheDir
                .appending(path: "bucket-\(bucket)")
                .appending(path: "file-\(index).bin")
            try payload.write(to: url)
        }
        return (root, marker)
    }

    @Test func scans2000SmallFilesInUnderTwoSeconds() async throws {
        let fileCount = 2_000
        let (root, marker) = try buildLargeTree(fileCount: fileCount)
        defer { try? FileManager.default.removeItem(at: root) }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "perf.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: root
        )

        let start = Date()
        let result = await scanner.scan()
        let elapsed = Date().timeIntervalSince(start)

        // Only count files inside our sandbox — system paths will leak in.
        let inSandbox = result.filesByCategory.values.flatMap { $0 }
            .filter { $0.url.path(percentEncoded: false).contains(marker) }
        #expect(inSandbox.count == fileCount)

        // 2 seconds is extremely generous for 2k small files on any modern
        // Mac; on an M-series laptop the real number is ~100ms. Flags
        // regressions without flaking.
        #expect(elapsed < 2.0, "Scan took \(String(format: "%.2f", elapsed))s — perf regression?")
    }
}
