import SwiftUI

/// Cumulative progress display for the scanning UI. Built by accumulating
/// the delta-style `ScanProgress` events emitted by the parallel scan tasks.
struct ScanDisplayProgress: Equatable {
    var totalFiles: Int = 0
    var totalSize: Int64 = 0
    var currentPath: String = ""
    var currentCategory: FileCategory? = nil
}

@MainActor
final class ScanViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case completed
    }

    @Published var state: State = .idle
    @Published var result: ScanResult = .empty
    @Published var sortedFilesByCategory: [FileCategory: [ScannedFile]] = [:]
    @Published var allSortedFiles: [ScannedFile] = []
    @Published var displayProgress: ScanDisplayProgress = ScanDisplayProgress()
    @Published var tmSnapshots: [TMSnapshot] = []
    @Published var hasFullDiskAccess: Bool = false

    private let exclusionManager: ExclusionManager
    private let appState: AppState

    init(exclusionManager: ExclusionManager, appState: AppState) {
        self.exclusionManager = exclusionManager
        self.appState = appState
        self.hasFullDiskAccess = FullDiskAccess.check()
    }

    func startScan() async {
        state = .scanning
        displayProgress = ScanDisplayProgress()

        let classifier = CategoryClassifier(largeFileThresholdBytes: appState.largeFileThresholdBytes)
        let scanner = DiskScanner(classifier: classifier, exclusionManager: exclusionManager)

        let stream = await scanner.progressStream()
        let progressTask = Task { [weak self] in
            // Accumulate delta events from all parallel scan tasks. Throttle UI
            // updates to ~4/sec so the displayed numbers and path don't flicker.
            var totalFiles = 0
            var totalSize: Int64 = 0
            var lastUpdate = Date.distantPast
            let minInterval: TimeInterval = 0.25
            var lastPath = ""
            var lastCategory: FileCategory? = nil

            for await delta in stream {
                totalFiles += delta.deltaFiles
                totalSize += delta.deltaSize
                lastPath = delta.currentPath
                lastCategory = delta.category

                let now = Date()
                if now.timeIntervalSince(lastUpdate) >= minInterval {
                    lastUpdate = now
                    let snapshot = ScanDisplayProgress(
                        totalFiles: totalFiles,
                        totalSize: totalSize,
                        currentPath: lastPath,
                        currentCategory: lastCategory
                    )
                    await MainActor.run {
                        self?.displayProgress = snapshot
                    }
                }
            }

            // Final flush so the UI sees the full final values
            let finalSnapshot = ScanDisplayProgress(
                totalFiles: totalFiles,
                totalSize: totalSize,
                currentPath: lastPath,
                currentCategory: lastCategory
            )
            await MainActor.run {
                self?.displayProgress = finalSnapshot
            }
        }

        let scanResult = await scanner.scan()

        let snapshots = (try? await TimeMachineService.listSnapshots()) ?? []

        progressTask.cancel()

        // Pre-sort once so the UI doesn't re-sort on every selection toggle
        let sortedByCategory = scanResult.filesByCategory.mapValues { files in
            files.sorted { $0.size > $1.size }
        }
        let allSorted = sortedByCategory.values.flatMap { $0 }.sorted { $0.size > $1.size }

        self.result = scanResult
        self.sortedFilesByCategory = sortedByCategory
        self.allSortedFiles = allSorted
        self.tmSnapshots = snapshots
        self.state = .completed
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
