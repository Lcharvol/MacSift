import Testing
import Foundation
@testable import MacSift

/// End-to-end sanity check: scan a temp tree, feed every discovered file to
/// the cleaning engine, and verify the pipeline is internally consistent
/// (sizes match, dry-run leaves files alone, real run empties the tree).
/// The ViewModel layer is NOT exercised — it's @MainActor UI glue and its
/// logic is already covered by CleaningViewModelTests.
@Suite("Scan → Clean Integration")
struct ScanToCleanIntegrationTests {
    /// Each test gets a unique folder name like `MacSiftE2E-<uuid>`. Tests
    /// filter discovered files by this substring so results from global
    /// scan targets (`/tmp`, `/private/var/log`) don't leak into assertions.
    /// We use `contains` rather than a prefix match because
    /// FileManager.temporaryDirectory can be reported as `/var/folders/...`
    /// or `/private/var/folders/...` depending on how the enumerator resolves
    /// the path.
    private func makeTempDir() throws -> (url: URL, marker: String) {
        let marker = "MacSiftE2E-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory.appending(path: marker)
        let fm = FileManager.default

        let cacheDir = tempDir.appending(path: "Library/Caches/com.test.app")
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 1024).write(to: cacheDir.appending(path: "cache-a.db"))
        try Data(repeating: 0xBB, count: 2048).write(to: cacheDir.appending(path: "cache-b.db"))

        let logDir = tempDir.appending(path: "Library/Logs")
        try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        try Data(repeating: 0xCC, count: 4096).write(to: logDir.appending(path: "app.log"))

        return (tempDir, marker)
    }

    private func makeScanner(home: URL) async -> DiskScanner {
        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        return DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: home
        )
    }

    private func filesInSandbox(_ result: ScanResult, marker: String) -> [ScannedFile] {
        result.filesByCategory.values.flatMap { $0 }
            .filter { $0.url.path(percentEncoded: false).contains(marker) }
    }

    @Test func dryRunDoesNotRemoveScannedFiles() async throws {
        let (tempDir, marker) = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = await makeScanner(home: tempDir)
        let scanResult = await scanner.scan()
        let allFiles = filesInSandbox(scanResult, marker: marker)
        #expect(allFiles.count >= 3)

        let engine = CleaningEngine()
        let report = await engine.clean(files: allFiles, dryRun: true)

        #expect(report.deletedCount == allFiles.count)
        #expect(report.failedFiles.isEmpty)
        let expectedSize = allFiles.reduce(0 as Int64) { $0 + $1.size }
        #expect(report.freedSize == expectedSize)

        for file in allFiles {
            #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        }
    }

    @Test func realRunDeletesScannedFilesAndRescanFindsNothing() async throws {
        let (tempDir, marker) = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = await makeScanner(home: tempDir)
        let first = await scanner.scan()
        let allFiles = filesInSandbox(first, marker: marker)
        #expect(!allFiles.isEmpty)
        let expectedSize = allFiles.reduce(0 as Int64) { $0 + $1.size }

        let engine = CleaningEngine()
        let report = await engine.clean(files: allFiles, dryRun: false)

        #expect(report.deletedCount == allFiles.count)
        #expect(report.freedSize == expectedSize)
        #expect(report.failedFiles.isEmpty)

        let second = await scanner.scan()
        let remaining = filesInSandbox(second, marker: marker)
        #expect(remaining.isEmpty)
    }

    @Test func progressIsReportedForEveryFile() async throws {
        let (tempDir, marker) = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scanner = await makeScanner(home: tempDir)
        let scanResult = await scanner.scan()
        let allFiles = filesInSandbox(scanResult, marker: marker)
        #expect(!allFiles.isEmpty)

        let (stream, continuation) = AsyncStream.makeStream(of: CleaningProgress.self)
        async let collected: [CleaningProgress] = Task {
            var out: [CleaningProgress] = []
            for await event in stream { out.append(event) }
            return out
        }.value

        let engine = CleaningEngine()
        _ = await engine.clean(files: allFiles, dryRun: true, progress: continuation)
        continuation.finish()
        let events = await collected

        #expect(events.count == allFiles.count)
        for (index, event) in events.enumerated() {
            #expect(event.processed == index + 1)
            #expect(event.total == allFiles.count)
        }
    }
}
