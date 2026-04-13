import SwiftUI

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
    @Published var progress: ScanProgress?
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
        progress = nil

        let classifier = CategoryClassifier(largeFileThresholdBytes: appState.largeFileThresholdBytes)
        let scanner = DiskScanner(classifier: classifier, exclusionManager: exclusionManager)

        let stream = await scanner.progressStream()
        let progressTask = Task { [weak self] in
            // Throttle UI updates to ~4/sec so the displayed numbers and path don't flicker
            var lastUpdate = Date.distantPast
            let minInterval: TimeInterval = 0.25
            for await scanProgress in stream {
                let now = Date()
                if now.timeIntervalSince(lastUpdate) >= minInterval {
                    lastUpdate = now
                    await MainActor.run {
                        self?.progress = scanProgress
                    }
                }
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
