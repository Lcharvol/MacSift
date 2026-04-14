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
    /// Volumes that were scanned for this result, in display order (boot first).
    let volumes: [Volume]
    /// When this scan completed. Used by the UI to show "Last scanned X ago".
    let completedAt: Date

    static func == (lhs: CompletedScan, rhs: CompletedScan) -> Bool {
        lhs.result.scanDuration == rhs.result.scanDuration
            && lhs.allSortedFiles.count == rhs.allSortedFiles.count
            && lhs.tmSnapshots.count == rhs.tmSnapshots.count
            && lhs.volumes == rhs.volumes
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
    /// Mounted volumes discovered at the last scan. Populated before the
    /// scan dispatches so the sidebar can show them immediately.
    @Published var discoveredVolumes: [Volume] = []

    // Convenience accessors that read from the state's associated value
    var result: ScanResult { state.completedScan?.result ?? .empty }
    var sortedFilesByCategory: [FileCategory: [ScannedFile]] { state.completedScan?.sortedFilesByCategory ?? [:] }
    var allSortedFiles: [ScannedFile] { state.completedScan?.allSortedFiles ?? [] }
    var groupsByCategory: [FileCategory: [FileGroup]] { state.completedScan?.groupsByCategory ?? [:] }
    var allSortedGroups: [FileGroup] { state.completedScan?.allSortedGroups ?? [] }
    var tmSnapshots: [TMSnapshot] { state.completedScan?.tmSnapshots ?? [] }
    var scannedVolumes: [Volume] { state.completedScan?.volumes ?? [] }

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
        // Discover mounted volumes once at the start. When the user drops a
        // folder (customScanRoot non-nil), we fall back to single-root mode
        // and don't scan any volumes — the drop-folder flow doesn't care
        // about multi-disk.
        let volumes: [Volume]
        if customScanRoot == nil {
            volumes = VolumeDiscovery.list()
        } else {
            volumes = []
        }
        discoveredVolumes = volumes

        let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
        let progressTask = startProgressAccumulator(stream: stream)

        defer { continuation.finish() }

        let classifier = await CategoryClassifier.withInstalledApps(
            largeFileThresholdBytes: appState.largeFileThresholdBytes,
            oldDownloadsAgeThresholdDays: Double(appState.oldDownloadsAgeDays)
        )
        let exclusionManager = self.exclusionManager

        // Build one scanner per target. Drop-folder or empty volume list
        // (unit tests / unusual environments) fall back to a single boot
        // scanner pointed at customScanRoot / default home.
        struct Target: Sendable {
            let scanner: DiskScanner
            let isBoot: Bool
        }

        let targets: [Target]
        if volumes.isEmpty {
            targets = [Target(scanner: DiskScanner(
                classifier: classifier,
                exclusionManager: exclusionManager,
                homeDirectory: customScanRoot,
                mode: .boot
            ), isBoot: true)]
        } else {
            targets = volumes.map { volume in
                if volume.isBoot {
                    return Target(scanner: DiskScanner(
                        classifier: classifier,
                        exclusionManager: exclusionManager,
                        homeDirectory: nil, // real $HOME
                        mode: .boot,
                        volumeID: volume.id
                    ), isBoot: true)
                } else {
                    return Target(scanner: DiskScanner(
                        classifier: classifier,
                        exclusionManager: exclusionManager,
                        homeDirectory: volume.url,
                        mode: .externalVolume,
                        volumeID: volume.id
                    ), isBoot: false)
                }
            }
        }

        // Fan out one scan per volume in parallel. The progress continuation
        // is shared: all tasks yield into the same stream and the accumulator
        // aggregates deltas into one displayProgress.
        let scanResult: ScanResult = await withTaskGroup(of: ScanResult.self) { group in
            for target in targets {
                group.addTask { [continuation] in
                    await target.scanner.scan(progress: continuation)
                }
            }
            var mergedByCategory: [FileCategory: [ScannedFile]] = [:]
            var totalDuration: TimeInterval = 0
            var totalInaccessible = 0
            var aggregatedPaths: [String] = []
            for await partial in group {
                for (category, files) in partial.filesByCategory {
                    mergedByCategory[category, default: []].append(contentsOf: files)
                }
                totalDuration = max(totalDuration, partial.scanDuration)
                totalInaccessible += partial.inaccessibleCount
                for path in partial.inaccessiblePaths {
                    if aggregatedPaths.count >= DiskScanner.inaccessiblePathCap { break }
                    aggregatedPaths.append(path)
                }
            }
            return ScanResult(
                filesByCategory: mergedByCategory,
                scanDuration: totalDuration,
                inaccessibleCount: totalInaccessible,
                inaccessiblePaths: aggregatedPaths
            )
        }

        if Task.isCancelled {
            progressTask.cancel()
            state = .idle
            displayProgress = ScanDisplayProgress()
            return
        }

        let prepared = await prepareScanResult(scanResult)
        let snapshots: [TMSnapshot]
        do {
            snapshots = try await TimeMachineService.listSnapshots()
        } catch {
            MacSiftLog.warning("Failed to list Time Machine snapshots: \(error.localizedDescription)")
            snapshots = []
        }
        progressTask.cancel()

        let completed = buildCompletedScan(
            prepared: prepared,
            scanResult: scanResult,
            snapshots: snapshots,
            volumes: volumes
        )
        appState.lifetimeScanCount += 1
        state = .completed(completed)

        let volumesDesc = volumes.isEmpty ? "single root" : volumes.map(\.name).joined(separator: ", ")
        MacSiftLog.info("Scan completed across [\(volumesDesc)]: \(completed.result.totalFileCount) files, " +
            "\(completed.result.totalSize.formattedFileSize) in " +
            "\(String(format: "%.2fs", scanResult.scanDuration)) — " +
            "\(scanResult.inaccessibleCount) inaccessible")

        // Post a local notification if the scan took a while and the user
        // isn't looking at the window right now.
        ScanNotifications.notifyIfBackgroundLongScan(
            duration: scanResult.scanDuration,
            fileCount: completed.result.totalFileCount,
            totalSize: completed.result.totalSize
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
        snapshots: [TMSnapshot],
        volumes: [Volume]
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
                scanDuration: scanResult.scanDuration,
                inaccessibleCount: scanResult.inaccessibleCount,
                inaccessiblePaths: scanResult.inaccessiblePaths
            ),
            sortedFilesByCategory: byCategory,
            allSortedFiles: all,
            groupsByCategory: groupsByCategory,
            allSortedGroups: allGroups,
            tmSnapshots: snapshots,
            volumes: volumes,
            completedAt: Date()
        )
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
