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
    @Published var selectedFiles: Set<ScannedFile> = []
    @Published var report: CleaningReport?
    @Published var cleaningProgress: CleaningProgress?
    @Published var showPreview: Bool = false

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var selectedSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        selectedFiles.count
    }

    var selectedByCategory: [FileCategory: [ScannedFile]] {
        Dictionary(grouping: Array(selectedFiles), by: \.category)
    }

    func toggleFile(_ file: ScannedFile) {
        if selectedFiles.contains(file) {
            selectedFiles.remove(file)
        } else {
            selectedFiles.insert(file)
        }
    }

    func selectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        for file in files {
            selectedFiles.insert(file)
        }
    }

    func deselectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        for file in files {
            selectedFiles.remove(file)
        }
    }

    func selectAllSafe(from result: ScanResult) {
        for (category, files) in result.filesByCategory {
            if category.riskLevel == .safe {
                for file in files {
                    selectedFiles.insert(file)
                }
            }
        }
    }

    func showCleaningPreview() {
        guard !selectedFiles.isEmpty else { return }
        showPreview = true
        state = .previewing
    }

    func cancelPreview() {
        showPreview = false
        state = .idle
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
            files: Array(selectedFiles),
            dryRun: appState.isDryRun
        )

        progressTask.cancel()

        self.report = cleaningReport
        self.selectedFiles.removeAll()
        self.state = .completed
    }

    func reset() {
        state = .idle
        report = nil
        cleaningProgress = nil
        showPreview = false
    }
}
