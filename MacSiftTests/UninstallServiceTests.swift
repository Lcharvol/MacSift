import Testing
import Foundation
@testable import MacSift

/// Exercise the three testable halves of UninstallService — the
/// trash-the-running-bundle step is intentionally NOT covered here
/// because we can't safely trash the test runner's own .app bundle
/// during a unit test. That one is covered by manual testing and
/// by the shipped `FileManager.trashItem` contract.
@Suite("UninstallService")
struct UninstallServiceTests {
    // MARK: - clearUserDefaults

    @Test func clearUserDefaultsWipesEveryKeyInTheDomain() {
        let suite = "test.uninstall.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("advanced", forKey: "appMode")
        defaults.set(false, forKey: "isDryRun")
        defaults.set(1024, forKey: "largeFileThresholdMB")
        defaults.set(42, forKey: "lifetimeScanCount")

        UninstallService.clearUserDefaults(bundleID: suite)

        // Every key in the domain should now be gone. We re-read via a
        // fresh UserDefaults instance on the same suite to bypass any
        // in-memory caching.
        let reloaded = UserDefaults(suiteName: suite)!
        #expect(reloaded.object(forKey: "appMode") == nil)
        #expect(reloaded.object(forKey: "isDryRun") == nil)
        #expect(reloaded.object(forKey: "largeFileThresholdMB") == nil)
        #expect(reloaded.object(forKey: "lifetimeScanCount") == nil)

        // Cleanup.
        UserDefaults().removePersistentDomain(forName: suite)
    }

    // MARK: - clearLogs

    @Test func clearLogsRemovesEntireDirectory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "UninstallLogTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        // Write a dummy log file so the folder has content worth removing.
        let logFile = tempRoot.appending(path: "macsift.log")
        try "line one\nline two".data(using: .utf8)!.write(to: logFile)

        let removed = UninstallService.clearLogs(at: tempRoot)
        #expect(removed == true)
        #expect(!FileManager.default.fileExists(atPath: tempRoot.path(percentEncoded: false)))
    }

    @Test func clearLogsReturnsFalseWhenNothingToRemove() {
        let nonexistent = FileManager.default.temporaryDirectory
            .appending(path: "UninstallLogTest-\(UUID().uuidString)")
        #expect(UninstallService.clearLogs(at: nonexistent) == false)
    }

    // MARK: - clearDownloadedUpdates

    @Test func clearDownloadedUpdatesOnlyRemovesMatchingArtifacts() throws {
        let fakeDownloads = FileManager.default.temporaryDirectory
            .appending(path: "UninstallDownloadsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeDownloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeDownloads) }

        // Things that SHOULD be removed.
        let zip = fakeDownloads.appending(path: "MacSift-0.2.6.zip")
        try Data(repeating: 0xAA, count: 1024).write(to: zip)

        let extractedDir = fakeDownloads.appending(path: "MacSift-0.2.6")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 2048).write(to: extractedDir.appending(path: "MacSift.app.placeholder"))

        // Things that SHOULD NOT be removed — any filename not matching
        // the exact `MacSift-<version>` shape must be left alone.
        let unrelated = fakeDownloads.appending(path: "some-random-file.zip")
        try Data(repeating: 0xCC, count: 512).write(to: unrelated)

        let lookalike = fakeDownloads.appending(path: "MacSiftClone.zip")
        try Data(repeating: 0xDD, count: 512).write(to: lookalike)

        // A malicious-looking filename that has the prefix but an unsafe
        // version string — should NOT match because isSafeVersionString
        // rejects it.
        let dangerous = fakeDownloads.appending(path: "MacSift-../../evil.zip")
        try? Data(repeating: 0xEE, count: 512).write(to: dangerous)

        let summary = UninstallService.clearDownloadedUpdates(from: fakeDownloads)

        #expect(summary.removedCount == 2, "Expected 2 MacSift artifacts removed, got \(summary.removedCount)")
        #expect(summary.reclaimedBytes >= 1024 + 2048)

        // Verify unrelated files survived.
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: unrelated.path(percentEncoded: false)))
        #expect(fm.fileExists(atPath: lookalike.path(percentEncoded: false)))
    }

    @Test func clearDownloadedUpdatesHandlesEmptyDirectory() throws {
        let empty = FileManager.default.temporaryDirectory
            .appending(path: "UninstallDownloadsEmpty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }

        let summary = UninstallService.clearDownloadedUpdates(from: empty)
        #expect(summary.removedCount == 0)
        #expect(summary.reclaimedBytes == 0)
    }

    @Test func clearDownloadedUpdatesHandlesMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "UninstallDownloadsMissing-\(UUID().uuidString)")
        let summary = UninstallService.clearDownloadedUpdates(from: missing)
        #expect(summary.removedCount == 0)
        #expect(summary.reclaimedBytes == 0)
    }
}
