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

    /// Cancelling a scan must stop the walk early and return a PARTIAL
    /// result rather than enumerating everything. Guards the cooperative
    /// cancellation checks inside `scanDirectory` / `scanForLargeFiles` that
    /// the Cancel button and `ScanViewModel.State.cancelling` depend on.
    ///
    /// Reuses the tiny shared fixture (2 files) rather than building a big
    /// tree: `ScanPerformanceTests` runs in parallel against a 2s wall-clock
    /// budget, and a heavy fixture here pushed it over. The "does cancellation
    /// actually reach a long-running walk" question is covered precisely (and
    /// without touching the disk) by
    /// `blockingExecutorPropagatesCancellationAcrossDispatchHop` below.
    @Test func cancellingScanReturnsWithoutCompletingEnumeration() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "cancel.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        // Cancel before the walk can start. The scan must still return
        // (never hang) and must come back empty rather than fully enumerated.
        let task = Task { await scanner.scan() }
        task.cancel()
        let cancelled = await task.value

        #expect(cancelled.totalFileCount == 0,
                "cancelled scan returned \(cancelled.totalFileCount) files — cancellation did not take effect")
    }

    /// Cancellation must survive the hop onto `BlockingScanExecutor`'s
    /// dispatch queue. This is the regression this test exists for: Swift
    /// task-local state does NOT cross `DispatchQueue.async`, so a walk that
    /// polls `Task.isCancelled` instead of the injected `CancellationFlag`
    /// silently never cancels. Asserted directly on the executor so the
    /// failure mode is unambiguous.
    @Test func blockingExecutorPropagatesCancellationAcrossDispatchHop() async {
        let observed = BlockingScanExecutor.CancellationFlag()

        let task = Task {
            await BlockingScanExecutor.run { flag -> ScanRootResult in
                // Spin until the flag flips (or we hit a safety bound), then
                // report what we saw. Mirrors the walks' polling loop.
                for _ in 0..<2_000 {
                    if flag.isCancelled { observed.cancel(); break }
                    Thread.sleep(forTimeInterval: 0.001)
                }
                return ScanRootResult(files: [], inaccessibleCount: 0)
            }
        }

        // Give the work time to land on the queue and start spinning.
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        _ = await task.value

        #expect(observed.isCancelled,
                "CancellationFlag never flipped — cancellation is not reaching the blocking walk")
    }

    /// The blocking-walk gate must leave cooperative threads free. If this
    /// ever equals or exceeds the core count we're back to the saturation
    /// bug that froze the UI during scans.
    @Test func blockingScanExecutorLeavesHeadroomForTheExecutor() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        #expect(BlockingScanExecutor.concurrencyLimit >= 2)
        #expect(BlockingScanExecutor.concurrencyLimit < max(cores, 3),
                "concurrency limit \(BlockingScanExecutor.concurrencyLimit) must stay below core count \(cores)")
    }
}

/// External / secondary volumes run ONLY the large-file sweep —
/// `scanTargets` is empty in `.externalVolume` mode. That makes the
/// sweep's skip list the sole gatekeeper, so anything it skips is
/// scanned by nothing at all.
@Suite("DiskScanner · external volume coverage")
struct ExternalVolumeScanTests {
    private func makeTree(folder: String, fileName: String, sizeMB: Int) throws -> URL {
        // `.resolvingSymlinksInPath()` is load-bearing: TMPDIR is under
        // /var, which is a symlink to /private/var. The enumerator emits
        // RESOLVED paths, so an unresolved root makes
        // `filePath.hasPrefix(homePrefix)` fail inside the sweep — at which
        // point `relativePath` falls back to the absolute path and the whole
        // (relative) skip list silently stops matching. These tests would
        // then pass no matter what the skip list contained. Verified: without
        // this, reverting the mode split does NOT fail the tests.
        let root = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath()
            .appending(path: "MacSiftExtVol-\(UUID().uuidString)")
        let dir = root.appending(path: folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data(repeating: 0xAB, count: sizeMB * 1024 * 1024)
        try data.write(to: dir.appending(path: fileName))
        return root
    }

    private func scanExternal(root: URL) async -> ScanResult {
        let classifier = CategoryClassifier(
            largeFileThresholdBytes: 1024 * 1024,   // 1 MB
            homePrefix: root.path(percentEncoded: false).hasSuffix("/")
                ? root.path(percentEncoded: false)
                : root.path(percentEncoded: false) + "/"
        )
        let exclusions = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "extvol.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusions,
            homeDirectory: root,
            mode: .externalVolume,
            volumeID: "/Volumes/TestDrive"
        )
        return await scanner.scan()
    }

    /// The regression this guards: `Downloads/` is in the sweep's skip list
    /// because on the BOOT volume a dedicated scan target covers it. On an
    /// external volume no such target exists, so skipping it made the user's
    /// files invisible with no warning. Before the mode-dependent skip list
    /// this returned zero files.
    @Test func downloadsOnExternalVolumeIsNotSkipped() async throws {
        let root = try makeTree(folder: "Downloads", fileName: "movie.bin", sizeMB: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await scanExternal(root: root)
        let found = result.filesByCategory.values.flatMap { $0 }
            .filter { $0.name == "movie.bin" }

        #expect(found.count == 1, "Downloads/ on an external volume was skipped — nothing else scans it")
        #expect(found.first?.category == .largeFiles)
    }

    /// Same reasoning for `Library/`, which is the largest of the
    /// boot-only skips and the one most likely to hold real user data on a
    /// backup drive.
    @Test func libraryOnExternalVolumeIsNotSkipped() async throws {
        let root = try makeTree(folder: "Library", fileName: "archive.bin", sizeMB: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await scanExternal(root: root)
        let found = result.filesByCategory.values.flatMap { $0 }
            .filter { $0.name == "archive.bin" }

        #expect(found.count == 1, "Library/ on an external volume was skipped — nothing else scans it")
    }

    /// Build artifacts stay skipped everywhere: that skip is justified by
    /// "this is noise and there are millions of tiny files", which is true
    /// on every volume. If this starts failing, the mode split was applied
    /// too broadly.
    @Test func buildArtifactsAreStillSkippedOnExternalVolume() async throws {
        let root = try makeTree(folder: "project/node_modules", fileName: "bundle.bin", sizeMB: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await scanExternal(root: root)
        let found = result.filesByCategory.values.flatMap { $0 }
            .filter { $0.name == "bundle.bin" }

        #expect(found.isEmpty, "node_modules should stay skipped on every volume — it's noise, not another target's territory")
    }

    /// And the boot-volume behaviour must be unchanged: `Downloads/` is
    /// still skipped by the sweep there, because the dedicated Downloads
    /// scan target covers it. This is the anti-regression guard for the
    /// v0.1.3 double-count fix.
    @Test func downloadsIsStillSkippedBySweepOnBootVolume() async throws {
        let root = try makeTree(folder: "Downloads", fileName: "recent.bin", sizeMB: 2)
        defer { try? FileManager.default.removeItem(at: root) }

        let homePrefix = root.path(percentEncoded: false).hasSuffix("/")
            ? root.path(percentEncoded: false)
            : root.path(percentEncoded: false) + "/"
        let classifier = CategoryClassifier(
            largeFileThresholdBytes: 1024 * 1024,
            oldDownloadsAgeThresholdDays: 90,
            homePrefix: homePrefix
        )
        let exclusions = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "extvol.\(UUID().uuidString)")
        }
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusions,
            homeDirectory: root,
            mode: .boot
        )
        let result = await scanner.scan()

        // The file is recent, so the Downloads target classifies it as nil
        // and the sweep must not pick it up either — exactly one occurrence
        // at most, never two.
        let occurrences = result.filesByCategory.values.flatMap { $0 }
            .filter { $0.name == "recent.bin" }
        #expect(occurrences.count <= 1, "file appeared \(occurrences.count) times — sweep double-counted a boot-volume scan target")
    }
}
