import Testing
import Foundation
@testable import MacSift

@Suite("DiskScanner Integration")
struct DiskScannerIntegrationTests {
    private func createTempStructure() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftTest-\(UUID().uuidString)")
        let fm = FileManager.default

        let cacheDir = tempDir.appending(path: "Library/Caches/com.test.app")
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 1024).write(to: cacheDir.appending(path: "cache.db"))

        let logDir = tempDir.appending(path: "Library/Logs")
        try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 2048).write(to: logDir.appending(path: "app.log"))

        return tempDir
    }

    @Test func scansAndCategorizesFiles() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        let result = await scanner.scan()

        #expect(result.totalFileCount >= 2)
        #expect(result.filesByCategory[.cache]?.isEmpty == false)
        #expect(result.filesByCategory[.logs]?.isEmpty == false)
    }

    @Test func progressStreamEmitsDeltas() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        // Stream events into a collector that runs concurrently with the scan
        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)

        async let collected: [ScanProgress] = Task { () -> [ScanProgress] in
            var events: [ScanProgress] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }.value

        _ = await scanner.scan(progress: continuation)

        let events = await collected

        // At least one delta event should have been emitted for the files we created
        #expect(!events.isEmpty)
        // Every event carries non-negative deltas
        #expect(events.allSatisfy { $0.deltaFiles >= 0 && $0.deltaSize >= 0 })
        // Accumulated total matches what the scanner put on disk (1024 + 2048 bytes)
        let totalDeltaSize = events.reduce(0 as Int64) { $0 + $1.deltaSize }
        #expect(totalDeltaSize >= 1024 + 2048)
    }

    @Test func respectsExclusions() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        await MainActor.run {
            exclusionManager.addExclusion(tempDir.appending(path: "Library/Caches"))
        }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        let result = await scanner.scan()

        #expect(result.filesByCategory[.cache] == nil || result.filesByCategory[.cache]?.isEmpty == true)
        #expect(result.filesByCategory[.logs]?.isEmpty == false)
    }
}
