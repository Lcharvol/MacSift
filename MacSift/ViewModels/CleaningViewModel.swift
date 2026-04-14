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
    /// Backing storage for the current selection. Kept private so every
    /// mutation bumps `selectionVersion` — observers use the int instead
    /// of comparing the whole Set on each SwiftUI render.
    @Published private(set) var selectedIDs: Set<String> = []
    /// Increments on every mutation of `selectedIDs`. SwiftUI views
    /// should `onChange(of: selectionVersion)` instead of the Set itself
    /// — comparing a 10k-element Set for equality is O(n) per render.
    @Published private(set) var selectionVersion: Int = 0
    @Published var report: CleaningReport?
    @Published var cleaningProgress: CleaningProgress?
    @Published var showPreview: Bool = false

    /// Replace the selection wholesale. Bumps `selectionVersion` exactly once.
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
    private var indexBuildInnerTask: Task<[String: ScannedFile], Never>?

    init(appState: AppState) {
        self.appState = appState
    }

    func updateFileIndex(from result: ScanResult) {
        // Cancel any in-flight index build (both the outer wrapper AND the
        // detached inner task, because detached tasks don't inherit
        // cancellation from enclosing tasks).
        indexBuildInnerTask?.cancel()
        indexBuildTask?.cancel()

        let inner = Task.detached(priority: .userInitiated) { () -> [String: ScannedFile] in
            var dict: [String: ScannedFile] = [:]
            var counter = 0
            for files in result.filesByCategory.values {
                for file in files {
                    counter += 1
                    // Check cancellation periodically so an abandoned build
                    // stops walking within milliseconds of the cancel call.
                    if counter % 2000 == 0 && Task.isCancelled { return dict }
                    dict[file.id] = file
                }
            }
            return dict
        }
        indexBuildInnerTask = inner

        indexBuildTask = Task { [weak self] in
            let dict = await inner.value
            if Task.isCancelled { return }
            guard let self else { return }
            self.fileIndex = dict
            self.setSelectedIDs(self.selectedIDs.intersection(dict.keys))
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

    /// Build an aggregate summary from the current selection + the scan's
    /// grouped view. `allGroups` is typically `scanVM.allSortedGroups`.
    func selectionSummary(using allGroups: [FileGroup]) -> SelectionSummary {
        guard !selectedIDs.isEmpty else {
            return SelectionSummary(groupCount: 0, fileCount: 0, totalSize: 0, countByCategory: [:])
        }
        var groupCount = 0
        var fileCount = 0
        var total: Int64 = 0
        var counts: [FileCategory: Int] = [:]
        for group in allGroups {
            // A group counts if ANY of its files are selected (partial or full)
            let selectedFilesInGroup = group.files.filter { selectedIDs.contains($0.id) }
            guard !selectedFilesInGroup.isEmpty else { continue }
            groupCount += 1
            fileCount += selectedFilesInGroup.count
            total += selectedFilesInGroup.reduce(0) { $0 + $1.size }
            counts[group.category, default: 0] += selectedFilesInGroup.count
        }
        return SelectionSummary(
            groupCount: groupCount,
            fileCount: fileCount,
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
