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
            for await scanProgress in stream {
                await MainActor.run {
                    self?.progress = scanProgress
                }
            }
        }

        let scanResult = await scanner.scan()

        let snapshots = (try? await TimeMachineService.listSnapshots()) ?? []

        progressTask.cancel()

        self.result = scanResult
        self.tmSnapshots = snapshots
        self.state = .completed
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
