import SwiftUI

/// Cumulative progress display for the scanning UI. Built by accumulating
/// the delta-style `ScanProgress` events emitted by the parallel scan tasks.
struct ScanDisplayProgress: Equatable {
    var totalFiles: Int = 0
    var totalSize: Int64 = 0
    var currentPath: String = ""
    var currentCategory: FileCategory? = nil
    /// Per-category size breakdown, used to draw a live preview of the
    /// storage bar as the scan progresses.
    var sizeByCategory: [FileCategory: Int64] = [:]
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
    /// When this scan completed. Used by the UI to show "Last scanned X ago".
    let completedAt: Date

    static func == (lhs: CompletedScan, rhs: CompletedScan) -> Bool {
        lhs.result.scanDuration == rhs.result.scanDuration
            && lhs.allSortedFiles.count == rhs.allSortedFiles.count
            && lhs.tmSnapshots.count == rhs.tmSnapshots.count
            && lhs.completedAt == rhs.completedAt
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

    /// Folder to scan when non-nil. Defaults to the user's home directory.
    /// Set via `startScan(folder:)` when the user drops a folder on the window.
    private var customScanRoot: URL?

    func cancelScan() {
        if state.isScanning {
            state = .cancelling
        }
        currentScanTask?.cancel()
    }

    func startScan() {
        customScanRoot = nil
        launchScanTask()
    }

    func startScan(folder: URL) {
        customScanRoot = folder
        launchScanTask()
    }

    private func launchScanTask() {
        // Cancel any in-flight scan first
        currentScanTask?.cancel()
        state = .scanning
        displayProgress = ScanDisplayProgress()

        currentScanTask = Task { [weak self] in
            await self?.runScan()
        }
    }

    private struct Prepared: Sendable {
        let byCategory: [FileCategory: [ScannedFile]]
        let all: [ScannedFile]
        let groupsByCategory: [FileCategory: [FileGroup]]
        let allGroups: [FileGroup]
    }

    private func runScan() async {
        let scanner = await makeScanner()
        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let progressTask = startProgressAccumulator(stream: stream)

        let scanResult = await scanner.scan(progress: continuation)

        if Task.isCancelled {
            progressTask.cancel()
            state = .idle
            displayProgress = ScanDisplayProgress()
            return
        }

        let prepared = await prepareScanResult(scanResult)
        let snapshots = (try? await TimeMachineService.listSnapshots()) ?? []
        progressTask.cancel()

        let completed = buildCompletedScan(
            prepared: prepared,
            scanResult: scanResult,
            snapshots: snapshots
        )
        // Bump lifetime counter — one per completed (not cancelled) scan.
        appState.lifetimeScanCount += 1
        state = .completed(completed)

        // Post a local notification if the scan took a while and the user
        // isn't looking at the window right now.
        ScanNotifications.notifyIfBackgroundLongScan(
            duration: scanResult.scanDuration,
            fileCount: completed.result.totalFileCount,
            totalSize: completed.result.totalSize
        )
    }

    /// Build the scanner with the current settings and optional custom root.
    /// The classifier walks /Applications once to populate its installed-app
    /// set for orphan detection — this happens on a background thread.
    private func makeScanner() async -> DiskScanner {
        let classifier = await CategoryClassifier.withInstalledApps(
            largeFileThresholdBytes: appState.largeFileThresholdBytes
        )
        return DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: customScanRoot
        )
    }

    /// Consume delta progress events from the scanner and publish throttled
    /// cumulative snapshots to `displayProgress`. Capped at ~4 updates per second.
    private func startProgressAccumulator(stream: AsyncStream<ScanProgress>) -> Task<Void, Never> {
        Task { [weak self] in
            var totalFiles = 0
            var totalSize: Int64 = 0
            var sizeByCategory: [FileCategory: Int64] = [:]
            var lastUpdate = Date.distantPast
            let minInterval: TimeInterval = 0.25
            var lastPath = ""
            var lastCategory: FileCategory? = nil

            for await delta in stream {
                totalFiles += delta.deltaFiles
                totalSize += delta.deltaSize
                lastPath = delta.currentPath
                lastCategory = delta.category
                if let cat = delta.category {
                    sizeByCategory[cat, default: 0] += delta.deltaSize
                }

                let now = Date()
                if now.timeIntervalSince(lastUpdate) >= minInterval {
                    lastUpdate = now
                    let snapshot = ScanDisplayProgress(
                        totalFiles: totalFiles,
                        totalSize: totalSize,
                        currentPath: lastPath,
                        currentCategory: lastCategory,
                        sizeByCategory: sizeByCategory
                    )
                    await MainActor.run { self?.displayProgress = snapshot }
                }
            }

            // Final flush so the UI sees the full final values
            let finalSnapshot = ScanDisplayProgress(
                totalFiles: totalFiles,
                totalSize: totalSize,
                currentPath: lastPath,
                currentCategory: lastCategory,
                sizeByCategory: sizeByCategory
            )
            await MainActor.run { self?.displayProgress = finalSnapshot }
        }
    }

    /// Sort and group the raw scan result off the main thread. With 10k+ files
    /// this would otherwise freeze the UI for hundreds of milliseconds.
    private func prepareScanResult(_ scanResult: ScanResult) async -> Prepared {
        await Task.detached(priority: .userInitiated) {
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
    }

    /// Combine the prepared scan with TM snapshots and produce the final
    /// `CompletedScan` that will be published in a single assignment.
    private func buildCompletedScan(
        prepared: Prepared,
        scanResult: ScanResult,
        snapshots: [TMSnapshot]
    ) -> CompletedScan {
        // Inject TM snapshots as synthetic ScannedFile rows so they flow
        // through the same selection/cleaning UI as regular files.
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

        return CompletedScan(
            result: ScanResult(
                filesByCategory: byCategory,
                scanDuration: scanResult.scanDuration
            ),
            sortedFilesByCategory: byCategory,
            allSortedFiles: all,
            groupsByCategory: groupsByCategory,
            allSortedGroups: allGroups,
            tmSnapshots: snapshots,
            completedAt: Date()
        )
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
