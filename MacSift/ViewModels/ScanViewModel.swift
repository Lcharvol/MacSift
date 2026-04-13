import SwiftUI

/// Cumulative progress display for the scanning UI. Built by accumulating
/// the delta-style `ScanProgress` events emitted by the parallel scan tasks.
struct ScanDisplayProgress: Equatable {
    var totalFiles: Int = 0
    var totalSize: Int64 = 0
    var currentPath: String = ""
    var currentCategory: FileCategory? = nil
}

/// Bundled completed-scan state. Keeping the result, sorted views, and
/// snapshots together avoids a cascade of @Published notifications at the
/// end of a scan (which would each trigger an independent re-render).
struct CompletedScan: Equatable {
    let result: ScanResult
    let sortedFilesByCategory: [FileCategory: [ScannedFile]]
    let allSortedFiles: [ScannedFile]
    let groupsByCategory: [FileCategory: [FileGroup]]
    let allSortedGroups: [FileGroup]
    let tmSnapshots: [TMSnapshot]

    static func == (lhs: CompletedScan, rhs: CompletedScan) -> Bool {
        lhs.result.scanDuration == rhs.result.scanDuration
            && lhs.allSortedFiles.count == rhs.allSortedFiles.count
            && lhs.tmSnapshots.count == rhs.tmSnapshots.count
    }
}

@MainActor
final class ScanViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case cancelling
        case completed(CompletedScan)

        var isScanning: Bool {
            if case .scanning = self { return true }
            return false
        }

        var isCancelling: Bool {
            if case .cancelling = self { return true }
            return false
        }

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }

        var completedScan: CompletedScan? {
            if case .completed(let scan) = self { return scan }
            return nil
        }
    }

    @Published var state: State = .idle
    @Published var displayProgress: ScanDisplayProgress = ScanDisplayProgress()
    @Published var hasFullDiskAccess: Bool = false

    // Convenience accessors that read from the state's associated value
    var result: ScanResult { state.completedScan?.result ?? .empty }
    var sortedFilesByCategory: [FileCategory: [ScannedFile]] { state.completedScan?.sortedFilesByCategory ?? [:] }
    var allSortedFiles: [ScannedFile] { state.completedScan?.allSortedFiles ?? [] }
    var groupsByCategory: [FileCategory: [FileGroup]] { state.completedScan?.groupsByCategory ?? [:] }
    var allSortedGroups: [FileGroup] { state.completedScan?.allSortedGroups ?? [] }
    var tmSnapshots: [TMSnapshot] { state.completedScan?.tmSnapshots ?? [] }

    private let exclusionManager: ExclusionManager
    private let appState: AppState
    private var currentScanTask: Task<Void, Never>?

    init(exclusionManager: ExclusionManager, appState: AppState) {
        self.exclusionManager = exclusionManager
        self.appState = appState
        self.hasFullDiskAccess = FullDiskAccess.check()
    }

    func cancelScan() {
        if state.isScanning {
            state = .cancelling
        }
        currentScanTask?.cancel()
    }

    func startScan() {
        // Cancel any in-flight scan first
        currentScanTask?.cancel()
        state = .scanning
        displayProgress = ScanDisplayProgress()

        currentScanTask = Task { [weak self] in
            await self?.runScan()
        }
    }

    private func runScan() async {
        let classifier = CategoryClassifier(largeFileThresholdBytes: appState.largeFileThresholdBytes)
        let scanner = DiskScanner(classifier: classifier, exclusionManager: exclusionManager)

        // Construct the progress stream + continuation explicitly so we can
        // pass the continuation to scanner.scan and control its lifecycle.
        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)

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

        let scanResult = await scanner.scan(progress: continuation)

        if Task.isCancelled {
            progressTask.cancel()
            self.state = .idle
            self.displayProgress = ScanDisplayProgress()
            return
        }

        // Sort + group off the main thread — with 10k+ files this would freeze
        // the UI for hundreds of milliseconds at the end of the scan.
        struct Prepared: Sendable {
            let byCategory: [FileCategory: [ScannedFile]]
            let all: [ScannedFile]
            let groupsByCategory: [FileCategory: [FileGroup]]
            let allGroups: [FileGroup]
        }
        let prepared: Prepared = await Task.detached(priority: .userInitiated) {
            let byCategory = scanResult.filesByCategory.mapValues { files in
                files.sorted { $0.size > $1.size }
            }
            let all = byCategory.values.flatMap { $0 }.sorted { $0.size > $1.size }
            let groupsByCategory = byCategory.mapValues { FileGrouper.group($0) }
            let allGroups = groupsByCategory.values.flatMap { $0 }.sorted { $0.totalSize > $1.totalSize }
            return Prepared(
                byCategory: byCategory,
                all: all,
                groupsByCategory: groupsByCategory,
                allGroups: allGroups
            )
        }.value

        let snapshots = (try? await TimeMachineService.listSnapshots()) ?? []

        progressTask.cancel()

        // Inject TM snapshots as synthetic ScannedFile rows so they flow
        // through the same selection/cleaning UI as regular files. Snapshots
        // don't carry a real size from tmutil; use 0 as placeholder.
        let snapshotFiles: [ScannedFile] = snapshots.map { snap in
            ScannedFile(
                url: URL(filePath: "/Volumes/snapshot/\(snap.identifier)"),
                size: 0,
                category: .timeMachineSnapshots,
                description: "Local snapshot — \(snap.displayDate)",
                modificationDate: .now,
                isDirectory: false
            )
        }

        var byCategory = prepared.byCategory
        var all = prepared.all
        var groupsByCategory = prepared.groupsByCategory
        var allGroups = prepared.allGroups

        if !snapshotFiles.isEmpty {
            byCategory[.timeMachineSnapshots] = snapshotFiles
            all.append(contentsOf: snapshotFiles)

            let snapshotGroups = FileGrouper.group(snapshotFiles)
            groupsByCategory[.timeMachineSnapshots] = snapshotGroups
            allGroups.append(contentsOf: snapshotGroups)
            allGroups.sort { $0.totalSize > $1.totalSize }
        }

        let completed = CompletedScan(
            result: ScanResult(
                filesByCategory: byCategory,
                scanDuration: scanResult.scanDuration
            ),
            sortedFilesByCategory: byCategory,
            allSortedFiles: all,
            groupsByCategory: groupsByCategory,
            allSortedGroups: allGroups,
            tmSnapshots: snapshots
        )
        // Single @Published assignment instead of 5 cascading ones
        self.state = .completed(completed)
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
