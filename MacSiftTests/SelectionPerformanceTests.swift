import Testing
import Foundation
@testable import MacSift

/// Selection and summary perf smoke tests. These guard the optimizations
/// that fix the freeze users reported when selecting items after a large
/// scan: the stored `FileGroup.fileIDs` Set and the O(selected) rewrite
/// of `selectionSummary`.
///
/// Budgets are intentionally loose — orders of magnitude above the
/// optimized cost, but far below the regressed cost we're guarding
/// against. The pre-fix code would have taken ~seconds on 50 groups
/// with 1000 files each; post-fix it's well under 50ms.
@Suite("Selection Performance")
struct SelectionPerformanceTests {
    private func makeFile(_ id: String, size: Int64 = 1024, category: FileCategory = .cache) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/perf/\(id)"),
            size: size,
            category: category,
            description: "perf-fixture",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeGroup(label: String, files: [ScannedFile], category: FileCategory) -> FileGroup {
        FileGroup(
            id: "perfGroup-\(label)",
            label: label,
            category: category,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files,
            topFiles: Array(files.prefix(5)),
            mostRecentModificationDate: .now,
            representativeURL: URL(filePath: "/tmp/perf/\(label)"),
            fileIDs: Set(files.map(\.id))
        )
    }

    @Test("toggleGroup completes quickly on a large scan")
    func toggleGroupIsFast() async {
        // Realistic-ish shape: 50 groups × 1000 files each = 50k files.
        // Big enough that the pre-fix per-row Set allocation would show up;
        // small enough that the test stays fast on CI.
        let groupCount = 50
        let filesPerGroup = 1000
        var allFiles: [ScannedFile] = []
        var groups: [FileGroup] = []
        for g in 0..<groupCount {
            let files = (0..<filesPerGroup).map { i in
                makeFile("g\(g)-f\(i)")
            }
            allFiles.append(contentsOf: files)
            groups.append(makeGroup(label: "g\(g)", files: files, category: .cache))
        }

        let vm = await MainActor.run { CleaningViewModel(appState: AppState()) }
        await MainActor.run {
            var byCat: [FileCategory: [ScannedFile]] = [:]
            for f in allFiles { byCat[f.category, default: []].append(f) }
            vm.updateFileIndex(from: ScanResult(filesByCategory: byCat, scanDuration: 0), groups: groups)
        }
        // Let the detached index build settle. Sleep instead of yield —
        // yields run other Tasks on the current actor, not detached pool work.
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // Toggle every group on, then every group off. 100 mutations total.
        let start = Date()
        await MainActor.run {
            for group in groups { vm.toggleGroup(group) }
            for group in groups { vm.toggleGroup(group) }
        }
        let elapsed = Date().timeIntervalSince(start)

        // Pre-fix this regressed into the multi-second range on 50k files
        // because `group.fileIDs` recomputed the Set on every access. The
        // stored property makes it microseconds. 500ms is a very loose
        // ceiling that still catches a real regression.
        #expect(elapsed < 0.5, "toggleGroup ×100 took \(elapsed)s on 50k files (budget: 0.5s)")
    }

    @Test("selectionSummary runs in O(selected), not O(total)")
    func selectionSummaryDoesNotScanEveryFile() async {
        // 50 groups × 1000 files; select only one file. The new implementation
        // should walk just that one file via the fileIndex lookup, not the
        // whole 50k catalog.
        let groupCount = 50
        let filesPerGroup = 1000
        var allFiles: [ScannedFile] = []
        var groups: [FileGroup] = []
        for g in 0..<groupCount {
            let files = (0..<filesPerGroup).map { i in
                makeFile("g\(g)-f\(i)")
            }
            allFiles.append(contentsOf: files)
            groups.append(makeGroup(label: "g\(g)", files: files, category: .cache))
        }

        let vm = await MainActor.run { CleaningViewModel(appState: AppState()) }
        await MainActor.run {
            var byCat: [FileCategory: [ScannedFile]] = [:]
            for f in allFiles { byCat[f.category, default: []].append(f) }
            vm.updateFileIndex(from: ScanResult(filesByCategory: byCat, scanDuration: 0), groups: groups)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let singleSelectedID = allFiles[0].id
        await MainActor.run { vm.setSelectedIDs([singleSelectedID]) }

        // Run the summary 100 times; each run should be a single fileIndex
        // lookup. Pre-fix this was O(50k) per call on the main actor.
        let start = Date()
        for _ in 0..<100 {
            let summary = await MainActor.run { vm.selectionSummary(using: groups) }
            #expect(summary.fileCount == 1)
            #expect(summary.groupCount == 1)
        }
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.2, "selectionSummary ×100 on 50k catalog took \(elapsed)s (budget: 0.2s)")
    }
}
