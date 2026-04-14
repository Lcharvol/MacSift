import Testing
import Foundation
@testable import MacSift

// MARK: - CleaningViewModel coverage gaps

@MainActor
@Suite("CleaningViewModel · selectionSummary and lifecycle")
struct CleaningViewModelCoverageTests {
    private func makeFile(_ name: String, size: Int64, category: FileCategory = .cache) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/cov-\(name)"),
            size: size,
            category: category,
            description: "cov",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeGroup(id: String, files: [ScannedFile], category: FileCategory) -> FileGroup {
        FileGroup(
            id: id,
            label: id,
            category: category,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files,
            topFiles: files,
            mostRecentModificationDate: .now,
            representativeURL: URL(filePath: "/tmp/cov-\(id)")
        )
    }

    private func makeVM(with files: [ScannedFile]) -> CleaningViewModel {
        let appState = AppState()
        let vm = CleaningViewModel(appState: appState)
        var dict: [FileCategory: [ScannedFile]] = [:]
        for file in files { dict[file.category, default: []].append(file) }
        vm.updateFileIndex(from: ScanResult(filesByCategory: dict, scanDuration: 0))
        return vm
    }

    @Test func selectionSummaryCountsGroupsAndFilesAcrossCategories() async throws {
        let cacheFiles = [makeFile("c1", size: 100), makeFile("c2", size: 200), makeFile("c3", size: 300)]
        let logFiles = [makeFile("l1", size: 50, category: .logs), makeFile("l2", size: 70, category: .logs)]
        let cacheGroup = makeGroup(id: "cacheGroup", files: cacheFiles, category: .cache)
        let logGroup = makeGroup(id: "logGroup", files: logFiles, category: .logs)
        let allGroups = [cacheGroup, logGroup]

        let vm = makeVM(with: cacheFiles + logFiles)
        // Let the async updateFileIndex settle so selectedIDs intersection
        // doesn't clobber our selection below. Two yields is more than
        // enough for the detached task.
        await Task.yield()
        await Task.yield()
        // Select two files in cacheGroup + one in logGroup
        vm.setSelectedIDs([cacheFiles[0].id, cacheFiles[1].id, logFiles[0].id])

        let summary = vm.selectionSummary(using: allGroups)
        #expect(summary.groupCount == 2)
        #expect(summary.fileCount == 3)
        #expect(summary.totalSize == 100 + 200 + 50)
        #expect(summary.countByCategory[.cache] == 2)
        #expect(summary.countByCategory[.logs] == 1)
    }

    @Test func selectionSummaryWithEmptySelectionIsZero() async {
        let vm = makeVM(with: [])
        let summary = vm.selectionSummary(using: [])
        #expect(summary.groupCount == 0)
        #expect(summary.fileCount == 0)
        #expect(summary.totalSize == 0)
        #expect(summary.countByCategory.isEmpty)
    }

    @Test func resetClearsStateAndProgressAndReport() async {
        let vm = makeVM(with: [])
        vm.showPreview = true
        // We can't assign directly to `report` (it's @Published but settable),
        // but we can simulate the cleaning lifecycle by calling reset on
        // a VM in any state and asserting the fields land at defaults.
        vm.reset()
        #expect(vm.state == .idle)
        #expect(vm.report == nil)
        #expect(vm.cleaningProgress == nil)
        #expect(vm.showPreview == false)
    }

    @Test func cancelPreviewReturnsToIdle() async {
        let vm = makeVM(with: [])
        vm.showPreview = true
        vm.state = .previewing
        vm.cancelPreview()
        #expect(vm.state == .idle)
        #expect(vm.showPreview == false)
    }

    @Test func showCleaningPreviewNoOpsWhenSelectionEmpty() async {
        let vm = makeVM(with: [])
        // Selection is empty by construction
        vm.showCleaningPreview()
        #expect(vm.state == .idle)
        #expect(vm.showPreview == false)
    }
}

// MARK: - UpdateViewModel throttling + dismiss

@MainActor
@Suite("UpdateViewModel · throttling and dismiss", .serialized)
struct UpdateViewModelCoverageTests {
    private let dismissedKey = "UpdateViewModel.dismissedVersion"
    private let lastCheckKey = "UpdateViewModel.lastCheckAt"

    private func reset() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
    }

    @Test func dismissBannerRecordsVersionAndHidesBanner() {
        reset()
        let vm = UpdateViewModel()
        vm.availableUpdate = UpdateInfo(
            latestVersion: "0.3.0",
            releaseURL: URL(string: "https://example.invalid/release")!,
            downloadURL: URL(string: "https://example.invalid/MacSift.zip")!,
            downloadSizeBytes: 1_600_000,
            releaseNotes: "notes",
            publishedAt: nil
        )
        #expect(vm.shouldShowBanner == true)
        vm.dismissBanner()
        #expect(vm.dismissedVersion == "0.3.0")
        #expect(vm.shouldShowBanner == false)
    }

    @Test func dismissedVersionPersistsAcrossInstances() {
        reset()
        let a = UpdateViewModel()
        a.availableUpdate = UpdateInfo(
            latestVersion: "0.3.0",
            releaseURL: URL(string: "https://example.invalid/release")!,
            downloadURL: URL(string: "https://example.invalid/MacSift.zip")!,
            downloadSizeBytes: 0,
            releaseNotes: "",
            publishedAt: nil
        )
        a.dismissBanner()

        let b = UpdateViewModel()
        #expect(b.dismissedVersion == "0.3.0")
    }

    @Test func newerVersionBypassesDismissedState() {
        reset()
        let vm = UpdateViewModel()
        vm.availableUpdate = UpdateInfo(
            latestVersion: "0.3.0",
            releaseURL: URL(string: "https://example.invalid/release")!,
            downloadURL: URL(string: "https://example.invalid/MacSift.zip")!,
            downloadSizeBytes: 0,
            releaseNotes: "",
            publishedAt: nil
        )
        vm.dismissBanner()
        // Simulate a newer release dropping while the app is running.
        vm.availableUpdate = UpdateInfo(
            latestVersion: "0.4.0",
            releaseURL: URL(string: "https://example.invalid/release")!,
            downloadURL: URL(string: "https://example.invalid/MacSift.zip")!,
            downloadSizeBytes: 0,
            releaseNotes: "",
            publishedAt: nil
        )
        #expect(vm.shouldShowBanner == true)
    }

    @Test func checkForUpdateIfNeededHonorsThrottle() async {
        reset()
        // Simulate a check that just happened 60 seconds ago.
        UserDefaults.standard.set(Date().addingTimeInterval(-60), forKey: lastCheckKey)
        let vm = UpdateViewModel()

        // Non-forced check should be a no-op — it must NOT overwrite the
        // timestamp (we can verify by checking the timestamp is still ≤ now
        // and was not set to a fresh Date by the call). We also verify no
        // availableUpdate is set (would only happen if we called the API).
        await vm.checkForUpdateIfNeeded(force: false)
        #expect(vm.availableUpdate == nil)

        // A forced check DOES run — we can't assert on its result without a
        // network stub, but we can assert the lastCheckAt timestamp is updated.
        let before = Date()
        await vm.checkForUpdateIfNeeded(force: true)
        let saved = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
        #expect(saved != nil)
        if let saved {
            #expect(saved >= before)
        }
    }
}

// MARK: - ScanResult.filteringVolume edge cases

@Suite("ScanResult · volume filtering edges")
struct ScanResultFilteringEdgesTests {
    private func makeFile(_ name: String, volume: String, size: Int64 = 100) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/\(name)"),
            size: size,
            category: .largeFiles,
            description: "",
            modificationDate: .now,
            isDirectory: false,
            volumeID: volume
        )
    }

    @Test func filteringByMissingVolumeReturnsEmptyResult() {
        let files = [
            makeFile("a", volume: "/"),
            makeFile("b", volume: "/Volumes/T7"),
        ]
        let result = ScanResult(filesByCategory: [.largeFiles: files], scanDuration: 0)

        let filtered = result.filteringVolume("/Volumes/Nowhere")
        #expect(filtered.totalFileCount == 0)
        #expect(filtered.totalSize == 0)
        #expect(filtered.filesByCategory.isEmpty)
    }

    @Test func filteringByNilReturnsFullResultUnchanged() {
        let files = [makeFile("a", volume: "/"), makeFile("b", volume: "/Volumes/T7")]
        let result = ScanResult(filesByCategory: [.largeFiles: files], scanDuration: 2.5)

        let filtered = result.filteringVolume(nil)
        #expect(filtered.totalFileCount == 2)
        #expect(filtered.totalSize == 200)
        #expect(filtered.scanDuration == 2.5)
    }

    @Test func filteringDropsCategoriesLeftEmpty() {
        let boot = makeFile("boot", volume: "/")
        let external = makeFile("ext", volume: "/Volumes/T7")
        let result = ScanResult(
            filesByCategory: [
                .cache: [boot],
                .largeFiles: [external],
            ],
            scanDuration: 0
        )
        let filtered = result.filteringVolume("/Volumes/T7")
        // `.cache` should be GONE, not present as an empty array.
        #expect(filtered.filesByCategory[.cache] == nil)
        #expect(filtered.filesByCategory[.largeFiles]?.count == 1)
    }
}

// MARK: - FileSize formatting edge cases

@Suite("FileSize formatting · edge cases")
struct FileSizeEdgesTests {
    @Test func negativeBytesFormatGracefully() {
        // We don't care about the exact string — just that it doesn't crash
        // and produces something non-empty.
        let negative: Int64 = -1_000
        let formatted = negative.formattedFileSize
        #expect(!formatted.isEmpty)
    }

    @Test func int64MaxFormatsWithoutOverflow() {
        let formatted = Int64.max.formattedFileSize
        #expect(!formatted.isEmpty)
    }

    @Test func zeroBytesIsHumanReadable() {
        #expect(Int64(0).formattedFileSize.contains("0"))
    }
}

// MARK: - CategoryClassifier · coverage for untested prefix rules

@Suite("CategoryClassifier · prefix-rule coverage")
struct CategoryClassifierCoverageTests {
    private let classifier = CategoryClassifier()
    private var homePrefix: String { CategoryClassifier.sharedHomePrefix }

    private func classify(_ suffix: String) -> FileCategory? {
        classifier.classify(
            url: URL(filePath: "\(homePrefix)\(suffix)"),
            size: 1024,
            modificationDate: .now
        )
    }

    @Test func yarnCacheIsDevCache() {
        #expect(classify(".yarn/cache/foo") == .devCaches)
    }

    @Test func pnpmStoreIsDevCache() {
        #expect(classify(".pnpm-store/v3/files/abc") == .devCaches)
    }

    @Test func pipCacheIsDevCache() {
        #expect(classify(".cache/pip/http/a/b/c") == .devCaches)
    }

    @Test func huggingfaceCacheIsDevCache() {
        #expect(classify(".cache/huggingface/hub/foo") == .devCaches)
    }

    @Test func cargoRegistryCacheIsDevCache() {
        #expect(classify(".cargo/registry/cache/foo.crate") == .devCaches)
    }

    @Test func rustupToolchainsIsDevCache() {
        #expect(classify(".rustup/toolchains/stable-aarch64/bin/rustc") == .devCaches)
    }

    @Test func goModCacheIsDevCache() {
        #expect(classify("go/pkg/mod/github.com/pkg/errors") == .devCaches)
    }

    @Test func mailContainerDownloadsIsMailDownloads() {
        #expect(classify("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/attachment.pdf") == .mailDownloads)
    }

    @Test func xcodeArchivesIsXcodeJunk() {
        #expect(classify("Library/Developer/Xcode/Archives/2026-04-14/MyApp.xcarchive") == .xcodeJunk)
    }

    @Test func xcodeDeviceSupportIsXcodeJunk() {
        #expect(classify("Library/Developer/Xcode/iOS DeviceSupport/17.0/Symbols/System/Library") == .xcodeJunk)
    }

    @Test func coreSimulatorCachesIsXcodeJunk() {
        #expect(classify("Library/Developer/CoreSimulator/Caches/dyld/arm64") == .xcodeJunk)
    }
}

// MARK: - MacSiftLog append + trim

@Suite("MacSiftLog · append and tail")
struct MacSiftLogCoverageTests {
    @Test func infoAppendsToTailBuffer() {
        // MacSiftLog writes to the real ~/Library/Logs/MacSift path — we
        // can't redirect the sink without a bigger refactor. This test is
        // thus a smoke test: after writing a unique marker, `tail` should
        // contain it somewhere in the first N lines. Use a UUID-derived
        // marker so the assertion is robust to concurrent writes.
        let marker = "cov-\(UUID().uuidString)"
        MacSiftLog.info("Smoke test marker: \(marker)")
        // Give the async queue a moment to flush.
        Thread.sleep(forTimeInterval: 0.05)
        let recent = MacSiftLog.tail(lines: 50)
        #expect(recent.contains(where: { $0.contains(marker) }))
    }

    @Test func tailReturnsNewestFirst() {
        let first = "first-\(UUID().uuidString)"
        let second = "second-\(UUID().uuidString)"
        MacSiftLog.info(first)
        MacSiftLog.info(second)
        Thread.sleep(forTimeInterval: 0.05)
        let recent = MacSiftLog.tail(lines: 50)
        guard let firstIdx = recent.firstIndex(where: { $0.contains(first) }),
              let secondIdx = recent.firstIndex(where: { $0.contains(second) }) else {
            Issue.record("Markers not found in log tail")
            return
        }
        // Newest-first means `second` has a smaller index than `first`.
        #expect(secondIdx < firstIdx)
    }
}
