import Testing
import Foundation
@testable import MacSift

@MainActor
@Suite("CleaningViewModel")
struct CleaningViewModelTests {
    private func makeFile(_ name: String, size: Int64) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/group-test-\(name)"),
            size: size,
            category: .cache,
            description: "test",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeGroup(files: [ScannedFile]) -> FileGroup {
        FileGroup(
            id: "test-group-\(UUID().uuidString)",
            label: "Test group",
            category: .cache,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files,
            topFiles: files,
            mostRecentModificationDate: .now,
            representativeURL: URL(filePath: "/tmp/group-test"),
            fileIDs: Set(files.map(\.id))
        )
    }

    private func makeVM(with files: [ScannedFile]) -> CleaningViewModel {
        let appState = AppState()
        let vm = CleaningViewModel(appState: appState)
        var dict: [FileCategory: [ScannedFile]] = [:]
        for file in files {
            dict[file.category, default: []].append(file)
        }
        let result = ScanResult(filesByCategory: dict, scanDuration: 0)
        vm.updateFileIndex(from: result, groups: [])
        // updateFileIndex runs asynchronously — give it a moment to settle.
        // In production we'd wait on the internal Task, but for tests we can
        // just call it and then directly set the index via the public API.
        return vm
    }

    @Test func toggleGroupSelectsAllFilesWhenNoneSelected() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Directly seed selectedIDs via toggleGroup (no prior selection)
        vm.toggleGroup(group)

        #expect(vm.selectedIDs.count == 3)
        #expect(vm.selectedIDs.isSuperset(of: Set(files.map(\.id))))
    }

    @Test func toggleGroupDeselectsAllFilesWhenAllSelected() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Pre-select all
        vm.setSelectedIDs(Set(files.map(\.id)))

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.isEmpty)
    }

    @Test func toggleGroupOnPartiallySelectedSelectsAll() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Select only one
        vm.setSelectedIDs([files[0].id])

        vm.toggleGroup(group)

        // Partial → full
        #expect(vm.selectedIDs.count == 3)
    }

    @Test func keepOldestInDuplicateSetSelectsAllButTheOldest() async {
        let now = Date()
        let olderDate = now.addingTimeInterval(-86_400 * 30)  // 30 days ago
        let newestDate = now.addingTimeInterval(-3_600)        // 1 hour ago

        let oldest = ScannedFile(
            url: URL(filePath: "/tmp/original.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: olderDate,
            isDirectory: false
        )
        let middle = ScannedFile(
            url: URL(filePath: "/tmp/copy-a.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: now.addingTimeInterval(-86_400),
            isDirectory: false
        )
        let newest = ScannedFile(
            url: URL(filePath: "/tmp/copy-b.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: newestDate,
            isDirectory: false
        )
        let set = DuplicateSet(id: "hash", size: 2_000_000, files: [middle, newest, oldest])

        let vm = makeVM(with: [oldest, middle, newest])
        await Task.yield()
        await Task.yield()
        vm.keepOldestInDuplicateSet(set)

        // The oldest is NOT in the selection; both newer copies ARE.
        #expect(!vm.selectedIDs.contains(oldest.id))
        #expect(vm.selectedIDs.contains(middle.id))
        #expect(vm.selectedIDs.contains(newest.id))
        #expect(vm.selectedIDs.count == 2)
    }

    // MARK: - Cached selection aggregates
    //
    // `selectedSize` is an O(1) read of a value maintained in
    // `setSelectedIDs`, and `groupedSelection()` is memoized and invalidated
    // on every selection mutation. These tests lock in that the caches stay
    // correct across all three mutation paths: a wholesale `setSelectedIDs`,
    // a `toggleGroup`, and an async `updateFileIndex` rebuild (which
    // intersects the selection against the new index).

    /// Spin until the detached index build has landed. Readiness is probed by
    /// selecting a known file and checking its size shows up in the cached
    /// aggregate — the selection is cleared again before returning. Detached
    /// work doesn't run on this actor, so a plain `Task.yield()` is not enough,
    /// and a fixed sleep is both slower and flakier.
    private func waitForIndex(_ vm: CleaningViewModel, probe: ScannedFile) async {
        for _ in 0..<300 {
            vm.setSelectedIDs([probe.id])
            if vm.selectedSize == probe.size {
                vm.setSelectedIDs([])
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        vm.setSelectedIDs([])
    }

    @Test func selectedSizeIsCorrectAfterSetSelectedIDs() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let vm = makeVM(with: files)
        await waitForIndex(vm, probe: files[0])

        vm.setSelectedIDs([files[0].id, files[2].id])
        #expect(vm.selectedSize == 400)
        #expect(vm.selectedCount == 2)

        // Replacing the selection must not accumulate — it replaces.
        vm.setSelectedIDs([files[1].id])
        #expect(vm.selectedSize == 200)
        #expect(vm.selectedCount == 1)

        vm.setSelectedIDs([])
        #expect(vm.selectedSize == 0)
    }

    @Test func selectedSizeAndGroupingAreCorrectAfterToggleGroup() async {
        let cacheFiles = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let bigFile = ScannedFile(
            url: URL(filePath: "/tmp/group-test-big.bin"),
            size: 1_000,
            category: .largeFiles,
            description: "test",
            modificationDate: .now,
            isDirectory: false
        )
        let group = makeGroup(files: cacheFiles)

        let vm = makeVM(with: cacheFiles + [bigFile])
        await waitForIndex(vm, probe: bigFile)

        vm.setSelectedIDs([bigFile.id])
        #expect(vm.selectedSize == 1_000)

        // Select the group on top of the existing selection.
        vm.toggleGroup(group)
        #expect(vm.selectedSize == 1_300)

        let grouped = vm.groupedSelection()
        #expect(grouped[.cache]?.count == 2)
        #expect(grouped[.largeFiles]?.count == 1)
        #expect(grouped.keys.count == 2)

        // Toggling the group back off must invalidate the memo, not serve
        // the stale dictionary built above.
        vm.toggleGroup(group)
        #expect(vm.selectedSize == 1_000)
        let afterDeselect = vm.groupedSelection()
        #expect(afterDeselect[.cache] == nil)
        #expect(afterDeselect[.largeFiles]?.count == 1)
    }

    @Test func cachedAggregatesAreRecomputedWhenTheFileIndexIsReplaced() async {
        let fileA = makeFile("keepme", size: 100)
        let fileB = makeFile("goaway", size: 900)
        let vm = makeVM(with: [fileA, fileB])
        await waitForIndex(vm, probe: fileB)

        vm.setSelectedIDs([fileA.id, fileB.id])
        #expect(vm.selectedSize == 1_000)
        #expect(vm.groupedSelection()[.cache]?.count == 2)

        // Simulate a re-scan where fileB no longer exists on disk. The
        // index-rebuild path intersects the selection with the new index, so
        // the cached size and the grouped memo must both drop fileB.
        let newResult = ScanResult(filesByCategory: [.cache: [fileA]], scanDuration: 0)
        vm.updateFileIndex(from: newResult, groups: [])
        // Wait for the rebuild to land: the intersection drops fileB, so the
        // cached size settles at fileA's 100 bytes.
        for _ in 0..<300 {
            if vm.selectedSize == 100 && vm.selectedCount == 1 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(vm.selectedSize == 100)
        #expect(vm.selectedCount == 1)
        #expect(vm.selectedIDs == [fileA.id])
        let grouped = vm.groupedSelection()
        #expect(grouped[.cache]?.count == 1)
        #expect(grouped[.cache]?.first?.id == fileA.id)
    }

    @Test func groupedSelectionMatchesSelectedFilesAfterEveryMutation() async {
        let files = [
            makeFile("a", size: 10),
            makeFile("b", size: 20),
            makeFile("c", size: 30),
            makeFile("d", size: 40)
        ]
        let vm = makeVM(with: files)
        await waitForIndex(vm, probe: files[3])

        for selection in [
            Set([files[0].id]),
            Set([files[0].id, files[1].id, files[2].id]),
            Set<String>(),
            Set(files.map(\.id))
        ] {
            vm.setSelectedIDs(selection)
            let grouped = vm.groupedSelection()
            let flattened = grouped.values.flatMap { $0 }
            #expect(Set(flattened.map(\.id)) == selection)
            #expect(vm.selectedSize == flattened.reduce(0) { $0 + $1.size })
        }
    }

    @Test func toggleGroupDoesNotAffectUnrelatedSelection() async {
        let groupFiles = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let otherFile = makeFile("other", size: 500)
        let group = makeGroup(files: groupFiles)

        let vm = makeVM(with: groupFiles + [otherFile])
        vm.setSelectedIDs([otherFile.id])

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.contains(otherFile.id))
        #expect(vm.selectedIDs.count == 3)  // otherFile + both group files
    }
}

@MainActor
@Suite("CleaningViewModel · dry-run progress throttling")
struct CleaningProgressThrottleTests {
    private func makeFiles(_ count: Int) -> [ScannedFile] {
        (0..<count).map { i in
            ScannedFile(
                url: URL(filePath: "/tmp/throttle-test-\(i)"),
                size: 1024,
                category: .cache,
                description: "test",
                modificationDate: .now,
                isDirectory: false
            )
        }
    }

    /// The throttle buffers events at ~4/sec, which means the final event
    /// is almost always the one that gets buffered rather than published.
    /// `confirmCleaning` must flush it after the stream closes, otherwise
    /// the sheet is left showing a stale intermediate count forever.
    ///
    /// This fails if the flush is removed, or if the consumer task is
    /// cancelled instead of drained (the ordering bug: cancelling while
    /// the loop is suspended on the stream drops the buffered event).
    @Test func dryRunProgressEndsOnExactTotal() async {
        let appState = AppState()
        appState.isDryRun = true
        let vm = CleaningViewModel(appState: appState)

        let files = makeFiles(5_000)
        let result = ScanResult(filesByCategory: [.cache: files], scanDuration: 0)
        vm.updateFileIndex(from: result, groups: [])
        // Let the detached index build land before selecting.
        try? await Task.sleep(nanoseconds: 300_000_000)
        vm.setSelectedIDs(Set(files.map(\.id)))

        await vm.confirmCleaning()

        let progress = vm.cleaningProgress
        #expect(progress != nil, "progress should have been published at least once")
        // The decisive assertion: the LAST published value is the complete
        // one, not whatever the throttle happened to be holding.
        #expect(
            progress?.processed == progress?.total,
            "final published progress was \(progress?.processed ?? -1)/\(progress?.total ?? -1) — the buffered final event was dropped"
        )
        #expect(progress?.total == 5_000)
    }

    /// Guards the actual perf fix: the consumer must NOT publish once per
    /// file. We can't count main-actor hops directly, so we assert the
    /// observable consequence — a 5k-file dry run completes fast. An
    /// unthrottled consumer does 5k main-actor hops plus 5k SwiftUI
    /// invalidations and is dramatically slower.
    @Test func dryRunOfManyFilesCompletesQuickly() async {
        let appState = AppState()
        appState.isDryRun = true
        let vm = CleaningViewModel(appState: appState)

        let files = makeFiles(5_000)
        let result = ScanResult(filesByCategory: [.cache: files], scanDuration: 0)
        vm.updateFileIndex(from: result, groups: [])
        try? await Task.sleep(nanoseconds: 300_000_000)
        vm.setSelectedIDs(Set(files.map(\.id)))

        let start = Date()
        await vm.confirmCleaning()
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 2.0, "5k-file dry run took \(String(format: "%.2f", elapsed))s — throttling may have regressed")
    }
}
