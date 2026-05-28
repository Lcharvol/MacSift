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
        selectionVersion &+= 1
    }

    private let appState: AppState
    // Index for O(1) lookup by ID — populated when the scan completes
    private var fileIndex: [String: ScannedFile] = [:]
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
            self.setSelectedIDs(self.selectedIDs.intersection(built.fileIndex.keys))
        }
    }

    var selectedFiles: [ScannedFile] {
        selectedIDs.compactMap { fileIndex[$0] }
    }

    var selectedSize: Int64 {
        selectedIDs.reduce(0) { acc, id in
            acc + (fileIndex[id]?.size ?? 0)
        }
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

    var selectedByCategory: [FileCategory: [ScannedFile]] {
        Dictionary(grouping: selectedFiles, by: \.category)
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
        // Guarantee the stream is finished no matter what happens below —
        // without it, any early exit would leave `progressTask` hanging
        // forever on an unterminated AsyncStream iterator.
        defer { continuation.finish() }

        let progressTask = Task { [weak self] in
            for await progress in stream {
                await MainActor.run {
                    self?.cleaningProgress = progress
                }
            }
        }
        defer { progressTask.cancel() }

        let cleaningReport = await engine.clean(
            files: selectedFiles,
            dryRun: appState.isDryRun,
            progress: continuation
        )

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
