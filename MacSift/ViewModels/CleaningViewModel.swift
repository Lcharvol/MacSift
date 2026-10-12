import SwiftUI

@MainActor
final class CleaningViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case previewing
        case cleaning
        case completed
    }

    @Published var state: State = .idle
    /// Current selection. Intentionally NOT `@Published` — observers read
    /// it through the VM in their body, but mutations are signalled via
    /// the `selectionVersion` integer below. Publishing both fired
    /// `objectWillChange` twice per click, doubling SwiftUI render work
    /// for no behavioral gain.
    private(set) var selectedIDs: Set<String> = []
    /// Sole `@Published` signal for selection changes. Increments on every
    /// mutation. SwiftUI invalidates any view observing the VM as soon as
    /// this fires; that view's next body re-reads `selectedIDs` fresh.
    /// Comparing a Set with thousands of entries via `Equatable` in
    /// `onChange(of:)` is O(n); comparing an Int is O(1).
    @Published private(set) var selectionVersion: Int = 0
    @Published var report: CleaningReport?
    @Published var cleaningProgress: CleaningProgress?
    @Published var showPreview: Bool = false

    /// Replace the selection wholesale. Bumps `selectionVersion` exactly
    /// once — that's the only signal SwiftUI needs to invalidate observers.
    func setSelectedIDs(_ newValue: Set<String>) {
        selectedIDs = newValue
        // Invalidate the derived caches. They are rebuilt LAZILY on the next
        // read, not eagerly here: `toggleGroup` is called in loops (select-all
        // across 50 groups) and an eager O(selected) recompute per mutation
        // reintroduced the very freeze we're fixing. Lazy invalidation makes a
        // burst of N mutations cost O(N) and pay for exactly one rebuild.
        invalidateSelectionCaches()
        selectionVersion &+= 1
    }

    /// Mark every derived selection aggregate stale. Must be called after ANY
    /// mutation of `selectedIDs` OR of `fileIndex` — an index rebuild changes
    /// the sizes and categories the caches were derived from even when the
    /// selection set itself is unchanged.
    private func invalidateSelectionCaches() {
        cachedSelectedSize = nil
        cachedSelectedByCategory = nil
    }

    private let appState: AppState
    // Index for O(1) lookup by ID — populated when the scan completes
    private var fileIndex: [String: ScannedFile] = [:]
    /// Memoized total byte size of the current selection. `nil` means "stale";
    /// the next `selectedSize` read rebuilds it in one O(selected) pass.
    private var cachedSelectedSize: Int64?
    /// Memoized per-category view of the selection. `nil` means "stale" —
    /// the next read rebuilds it in one O(selected) pass. Invalidated by
    /// `setSelectedIDs` and by an index rebuild.
    private var cachedSelectedByCategory: [FileCategory: [ScannedFile]]?
    /// Tracks the in-flight updateFileIndex task so a rapid re-scan can
    /// cancel the previous build before it overwrites a fresher index.
    private var indexBuildTask: Task<Void, Never>?
    /// The detached inner task that actually walks the file tree. Kept as
    /// a separate handle so we can cancel it directly — `Task.detached`
    /// does NOT inherit cancellation from the surrounding task, so the
    /// outer cancellation alone would let the heavy work keep running.
    private var indexBuildInnerTask: Task<IndexBuildResult, Never>?

    /// Result of the off-main index build. Both lookups are O(1) and are
    /// reused by `selectionSummary` so it doesn't have to walk every file
    /// of every group on every selection mutation.
    private struct IndexBuildResult: Sendable {
        let fileIndex: [String: ScannedFile]
        /// For every file id, the id of the `FileGroup` that contains it.
        /// Lets `selectionSummary` count distinct selected groups in
        /// O(selected) instead of O(sum of all group sizes).
        let fileToGroupID: [String: String]
    }

    init(appState: AppState) {
        self.appState = appState
    }

    /// For every file id, the id of the `FileGroup` that contains it.
    /// Populated alongside `fileIndex` so `selectionSummary` can count
    /// distinct selected groups in O(selected) instead of O(total files).
    private var fileToGroupID: [String: String] = [:]

    func updateFileIndex(from result: ScanResult, groups: [FileGroup]) {
        // Cancel any in-flight index build (both the outer wrapper AND the
        // detached inner task, because detached tasks don't inherit
        // cancellation from enclosing tasks).
        indexBuildInnerTask?.cancel()
        indexBuildTask?.cancel()

        let inner = Task.detached(priority: .userInitiated) { () -> IndexBuildResult in
            var dict: [String: ScannedFile] = [:]
            var ownerByID: [String: String] = [:]
            var counter = 0
            for files in result.filesByCategory.values {
                for file in files {
                    counter += 1
                    // Check cancellation periodically so an abandoned build
                    // stops walking within milliseconds of the cancel call.
                    if counter % 2000 == 0 && Task.isCancelled {
                        return IndexBuildResult(fileIndex: dict, fileToGroupID: ownerByID)
                    }
                    dict[file.id] = file
                }
            }
            // Build the file→group reverse index from the supplied groups.
            // Cheap relative to the file walk above — each file appears in
            // exactly one group, so this is O(total files) total.
            for group in groups {
                let groupID = group.id
                for fileID in group.fileIDs {
                    ownerByID[fileID] = groupID
                }
                if counter & 0xFFF == 0 && Task.isCancelled {
                    return IndexBuildResult(fileIndex: dict, fileToGroupID: ownerByID)
                }
                counter += 1
            }
            return IndexBuildResult(fileIndex: dict, fileToGroupID: ownerByID)
        }
        indexBuildInnerTask = inner

        indexBuildTask = Task { [weak self] in
            let built = await inner.value
            if Task.isCancelled { return }
            guard let self else { return }
            self.fileIndex = built.fileIndex
            self.fileToGroupID = built.fileToGroupID
            // Assign the fresh index BEFORE narrowing the selection: the
            // `setSelectedIDs` call below invalidates the cached aggregates
            // (`selectedSize`, grouped selection), and their next rebuild must
            // read the NEW index. Reordering these lines would rebuild the
            // caches off the old index and leave stale sizes after a re-scan.
            self.setSelectedIDs(self.selectedIDs.intersection(built.fileIndex.keys))
        }
    }

    var selectedFiles: [ScannedFile] {
        selectedIDs.compactMap { fileIndex[$0] }
    }

    /// Memoized: one O(selected) pass per selection change, then O(1) for
    /// every subsequent read until the next mutation. Previously this was a
    /// full O(selected) reduce over `fileIndex` on EVERY read, and
    /// `CleaningPreviewView` reads it up to five times per render pass while
    /// re-rendering on each `cleaningProgress` tick.
    var selectedSize: Int64 {
        if let cached = cachedSelectedSize { return cached }
        var total: Int64 = 0
        for id in selectedIDs {
            total += fileIndex[id]?.size ?? 0
        }
        cachedSelectedSize = total
        return total
    }

    /// Build an aggregate summary from the current selection. The signature
    /// still accepts `allGroups` so existing call sites compile, but it's
    /// unused — the actual work walks `selectedIDs` against the pre-built
    /// `fileIndex` and `fileToGroupID` reverse-index, which is O(selected)
    /// instead of O(sum of all group sizes). On big scans with thousands
    /// of selected files this is the difference between a freeze-y click
    /// and a noop.
    func selectionSummary(using allGroups: [FileGroup] = []) -> SelectionSummary {
        _ = allGroups
        guard !selectedIDs.isEmpty else {
            return SelectionSummary(groupCount: 0, fileCount: 0, totalSize: 0, countByCategory: [:])
        }
        var total: Int64 = 0
        var counts: [FileCategory: Int] = [:]
        var distinctGroups: Set<String> = []
        for id in selectedIDs {
            guard let file = fileIndex[id] else { continue }
            total += file.size
            counts[file.category, default: 0] += 1
            if let owner = fileToGroupID[id] {
                distinctGroups.insert(owner)
            }
        }
        return SelectionSummary(
            groupCount: distinctGroups.count,
            fileCount: counts.values.reduce(0, +),
            totalSize: total,
            countByCategory: counts
        )
    }

    var selectedCount: Int {
        selectedIDs.count
    }

    /// Per-category view of the selection, built at most once per selection
    /// change. Callers that read this inside a SwiftUI body MUST cache the
    /// result in `@State` and refresh it from
    /// `.onChange(of: cleaningVM.selectionVersion)` — see
    /// `CleaningPreviewView.cachedSelectedByCategory`. Reading it once per
    /// category in a `ForEach` used to rebuild the whole dictionary 11 times
    /// per render pass (11 × O(selected) hash lookups + 11 allocations).
    func groupedSelection() -> [FileCategory: [ScannedFile]] {
        if let cached = cachedSelectedByCategory { return cached }
        var grouped: [FileCategory: [ScannedFile]] = [:]
        for id in selectedIDs {
            guard let file = fileIndex[id] else { continue }
            grouped[file.category, default: []].append(file)
        }
        cachedSelectedByCategory = grouped
        return grouped
    }

    var selectedByCategory: [FileCategory: [ScannedFile]] {
        groupedSelection()
    }

    func isSelected(_ file: ScannedFile) -> Bool {
        selectedIDs.contains(file.id)
    }

    func toggleFile(_ file: ScannedFile) {
        var next = selectedIDs
        if next.contains(file.id) {
            next.remove(file.id)
        } else {
            next.insert(file.id)
        }
        setSelectedIDs(next)
    }

    /// Toggle every file inside a `FileGroup`. If all files are already
    /// selected, deselect them all; otherwise select all of them.
    func toggleGroup(_ group: FileGroup) {
        let groupIDs = group.fileIDs
        var newSelection = selectedIDs
        if groupIDs.isSubset(of: newSelection) {
            newSelection.subtract(groupIDs)
        } else {
            newSelection.formUnion(groupIDs)
        }
        setSelectedIDs(newSelection)
    }

    func selectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        var newSelection = selectedIDs
        for file in files {
            newSelection.insert(file.id)
        }
        setSelectedIDs(newSelection)
    }

    func deselectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        var newSelection = selectedIDs
        for file in files {
            newSelection.remove(file.id)
        }
        setSelectedIDs(newSelection)
    }

    /// Select every file in the given duplicate set EXCEPT the one
    /// with the oldest `modificationDate`. The oldest copy is usually
    /// the "original" the user wants to keep — the newer copies are
    /// the accidental re-downloads. This is the default selection the
    /// duplicates view offers via its "Keep oldest, trash the rest"
    /// button; the user can still toggle individual rows afterwards.
    func keepOldestInDuplicateSet(_ set: DuplicateSet) {
        guard set.files.count > 1 else { return }
        guard let oldest = set.files.min(by: { $0.modificationDate < $1.modificationDate }) else { return }
        var newSelection = selectedIDs
        for file in set.files where file.id != oldest.id {
            newSelection.insert(file.id)
        }
        setSelectedIDs(newSelection)
    }

    func selectAllSafe(from result: ScanResult) {
        var newSelection = selectedIDs
        for (category, files) in result.filesByCategory where category.riskLevel == .safe {
            for file in files {
                newSelection.insert(file.id)
            }
        }
        setSelectedIDs(newSelection)
    }

    func showCleaningPreview() {
        guard !selectedIDs.isEmpty else { return }
        // Clear any stale report from a previous run
        report = nil
        cleaningProgress = nil
        showPreview = true
        state = .previewing
    }

    func cancelPreview() {
        showPreview = false
        state = .idle
        report = nil
        cleaningProgress = nil
    }

    func confirmCleaning() async {
        state = .cleaning

        let engine = CleaningEngine()

        let (stream, continuation) = AsyncStream<CleaningProgress>.makeStream()

        // Throttle to ~4 updates/sec (CLAUDE.md lesson #11). The engine
        // yields one event PER FILE — in dry run that's one main-actor hop
        // and one @Published invalidation for every one of potentially
        // 100k+ files, each re-rendering the cleaning sheet. Throttling
        // here rather than in the engine protects the real-deletion path
        // too, and keeps the engine's event granularity intact for tests.
        //
        // The final value is always flushed after the loop so the UI ends
        // on the exact totals rather than whatever the last tick happened
        // to be.
        let progressTask = Task { [weak self] in
            var lastUpdate = Date()
            let minInterval: TimeInterval = 0.25
            var pending: CleaningProgress?

            for await progress in stream {
                pending = progress
                let now = Date()
                if now.timeIntervalSince(lastUpdate) >= minInterval {
                    lastUpdate = now
                    await MainActor.run { self?.cleaningProgress = progress }
                    pending = nil
                }
            }

            // Flush the last buffered event so the final count is exact.
            if let pending, !Task.isCancelled {
                await MainActor.run { self?.cleaningProgress = pending }
            }
        }

        let cleaningReport = await engine.clean(
            files: selectedFiles,
            dryRun: appState.isDryRun,
            progress: continuation
        )

        // Close the stream and then WAIT for the consumer to drain it.
        // Order matters: `finish()` ends the `for await` loop so the
        // throttle's final flush can run, and awaiting the task lets that
        // flush land before we publish the report. Cancelling here instead
        // (the previous `defer { progressTask.cancel() }`) would kill the
        // loop while it was suspended on the stream, so the last buffered
        // progress event would be dropped and the sheet would be left
        // showing a stale throttled count instead of the exact total.
        continuation.finish()
        await progressTask.value

        // Bump the lifetime counter only for real (non-dry-run) cleanings.
        if !appState.isDryRun && cleaningReport.freedSize > 0 {
            appState.lifetimeCleanedBytes += cleaningReport.freedSize
        }

        if appState.isDryRun {
            MacSiftLog.info("Dry-run clean: \(cleaningReport.deletedCount) files, " +
                "\(cleaningReport.freedSize.formattedFileSize) would be freed")
        } else {
            MacSiftLog.info("Cleaned \(cleaningReport.deletedCount) files, " +
                "\(cleaningReport.freedSize.formattedFileSize) freed")
            if let destination = cleaningReport.firstTrashDestination {
                // Proves trashItem put files in the user's Trash rather than
                // hard-deleting them. Logs the first successful destination
                // for audit — other files land next to it.
                MacSiftLog.info("First trashed file → \(destination.path(percentEncoded: false))")
            } else if cleaningReport.deletedCount > 0 {
                MacSiftLog.warning("Cleaned \(cleaningReport.deletedCount) files but no Trash destination was captured — investigate.")
            }
        }
        for (file, reason) in cleaningReport.failedFiles {
            MacSiftLog.error("Failed to clean \(file.url.path(percentEncoded: false)): \(reason)")
        }

        self.report = cleaningReport
        self.setSelectedIDs([])
        self.state = .completed
    }

    func reset() {
        state = .idle
        report = nil
        cleaningProgress = nil
        showPreview = false
    }
}
