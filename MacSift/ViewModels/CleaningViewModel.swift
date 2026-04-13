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
    @Published var selectedIDs: Set<String> = []
    @Published var report: CleaningReport?
    @Published var cleaningProgress: CleaningProgress?
    @Published var showPreview: Bool = false

    private let appState: AppState
    // Index for O(1) lookup by ID — populated when the scan completes
    private var fileIndex: [String: ScannedFile] = [:]

    init(appState: AppState) {
        self.appState = appState
    }

    func updateFileIndex(from result: ScanResult) {
        // Build the index off the main thread to avoid blocking the UI when
        // the scan finishes (50k+ files = noticeable freeze).
        Task {
            let index: [String: ScannedFile] = await Task.detached(priority: .userInitiated) {
                var dict: [String: ScannedFile] = [:]
                for files in result.filesByCategory.values {
                    for file in files {
                        dict[file.id] = file
                    }
                }
                return dict
            }.value

            self.fileIndex = index
            // Drop selections whose files no longer exist in the latest scan
            self.selectedIDs = selectedIDs.intersection(index.keys)
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
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    func selectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        // Build the new set locally then assign once — avoids 1 @Published
        // notification per inserted item, which freezes the UI for large categories.
        var newSelection = selectedIDs
        for file in files {
            newSelection.insert(file.id)
        }
        selectedIDs = newSelection
    }

    func deselectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        var newSelection = selectedIDs
        for file in files {
            newSelection.remove(file.id)
        }
        selectedIDs = newSelection
    }

    func selectAllSafe(from result: ScanResult) {
        var newSelection = selectedIDs
        for (category, files) in result.filesByCategory where category.riskLevel == .safe {
            for file in files {
                newSelection.insert(file.id)
            }
        }
        selectedIDs = newSelection
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

        let stream = await engine.progressStream()
        let progressTask = Task { [weak self] in
            for await progress in stream {
                await MainActor.run {
                    self?.cleaningProgress = progress
                }
            }
        }

        let cleaningReport = await engine.clean(
            files: selectedFiles,
            dryRun: appState.isDryRun
        )

        progressTask.cancel()

        self.report = cleaningReport
        self.selectedIDs.removeAll()
        self.state = .completed
    }

    func reset() {
        state = .idle
        report = nil
        cleaningProgress = nil
        showPreview = false
    }
}
