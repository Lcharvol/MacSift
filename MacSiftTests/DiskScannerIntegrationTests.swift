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
        // The scanner no longer finishes the continuation itself (callers
        // own the stream in the multi-volume flow). Close it explicitly
        // here so the collector's `for await` loop exits.
        continuation.finish()

        let events = await collected

        // At least one delta event should have been emitted for the files we created
        #expect(!events.isEmpty)
        // Every event carries non-negative deltas
        #expect(events.allSatisfy { $0.deltaFiles >= 0 && $0.deltaSize >= 0 })
        // Accumulated total matches what the scanner put on disk (1024 + 2048 bytes)
        let totalDeltaSize = events.reduce(0 as Int64) { $0 + $1.deltaSize }
        #expect(totalDeltaSize >= 1024 + 2048)
    }

    /// Regression test for the v0.1.3 double-count bug. A file in
    /// `~/Downloads` that is BOTH older than the age threshold AND larger
    /// than `largeFileThresholdBytes` must appear exactly once, in
    /// `.oldDownloads`, not twice (once there and once in `.largeFiles`).
    /// The fix is that `scanForLargeFiles` adds `Downloads/` to its
    /// skipPrefixes — if that ever regresses, this test catches it.
    @Test func downloadsFilesAreNotDoubleCountedAcrossCategories() async throws {
        // This test CANNOT live under NSTemporaryDirectory() — the classifier's
        // tempFiles fallback check would match any path under /var/folders/
        // before we reach the Downloads rule. Nor can it live under /tmp
        // for the same reason. Drop it in a hidden folder inside the real
        // user home so the only path-rule that fires is the one we care
        // about: Downloads age-based classification.
        let tempDir = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .appending(path: ".macsift-dl-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fm = FileManager.default
        let downloadsDir = tempDir.appending(path: "Downloads")
        try fm.createDirectory(at: downloadsDir, withIntermediateDirectories: true)

        // 2 MB file that's also >90 days old — matches BOTH .largeFiles
        // (>1 MB threshold we'll configure below) and .oldDownloads.
        let fileURL = downloadsDir.appending(path: "old-and-large.bin")
        try Data(repeating: 0xEE, count: 2 * 1024 * 1024).write(to: fileURL)
        let oldDate = Date().addingTimeInterval(-120 * 86_400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: fileURL.path(percentEncoded: false))

        // Inject the sandbox home prefix so the classifier's path rules
        // match our fake ~/Downloads instead of the real user home.
        let tempHomePrefix: String = {
            let p = tempDir.path(percentEncoded: false)
            return p.hasSuffix("/") ? p : p + "/"
        }()
        let classifier = CategoryClassifier(
            largeFileThresholdBytes: 1 * 1024 * 1024,
            oldDownloadsAgeThresholdDays: 90,
            homePrefix: tempHomePrefix
        )
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        let result = await scanner.scan()

        // Count occurrences of the test file across ALL categories.
        // Use `contains` so /var vs /private/var symlink differences don't
        // mask a real match.
        let marker = "old-and-large.bin"
        let occurrences = result.filesByCategory.values
            .flatMap { $0 }
            .filter { $0.url.path(percentEncoded: false).hasSuffix(marker) }
        #expect(occurrences.count == 1, "Downloads file was counted in \(occurrences.count) categories — should be exactly 1. Found: \(occurrences.map(\.category))")
        #expect(occurrences.first?.category == .oldDownloads)
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
