import Foundation

/// A delta event from one of the parallel scan tasks. The consumer (ScanViewModel)
/// accumulates these into the displayed totals so the UI shows real cumulative
/// progress instead of bouncing between each task's local counters.
struct ScanProgress: Sendable {
    let deltaFiles: Int
    let deltaSize: Int64
    let currentPath: String
    let category: FileCategory?
}

/// Result of scanning a single root directory. Bundles the files found with
/// a count of items that couldn't be read (permission errors, broken links,
/// corrupted metadata). These are aggregated across all scan tasks.
struct ScanRootResult: Sendable {
    var files: [ScannedFile]
    var inaccessibleCount: Int
    /// Sample of unreadable paths from this scan task, capped at
    /// `DiskScanner.inaccessiblePathCap`. Aggregated into `ScanResult` for
    /// user-facing display — the full count stays in `inaccessibleCount`.
    var inaccessiblePaths: [String] = []
}

/// Small helper that buffers per-file delta counts and only yields a
/// `ScanProgress` event when the buffered count crosses the threshold.
/// Both scan functions had this pattern inline — extracting it keeps them
/// shorter and ensures the "final flush" semantics stay in sync.
private struct ProgressThrottler {
    let threshold: Int
    let category: FileCategory?
    let continuation: AsyncStream<ScanProgress>.Continuation?

    private var bufferedFiles = 0
    private var bufferedBytes: Int64 = 0

    init(threshold: Int, category: FileCategory?, continuation: AsyncStream<ScanProgress>.Continuation?) {
        self.threshold = threshold
        self.category = category
        self.continuation = continuation
    }

    mutating func add(bytes: Int64, currentPath: @autoclosure () -> String) {
        bufferedFiles += 1
        bufferedBytes += bytes
        if bufferedFiles >= threshold {
            flush(currentPath: currentPath())
        }
    }

    mutating func tick(currentPath: @autoclosure () -> String) {
        if bufferedFiles >= threshold {
            flush(currentPath: currentPath())
        }
    }

    mutating func flush(currentPath: String) {
        guard bufferedFiles > 0 else { return }
        continuation?.yield(ScanProgress(
            deltaFiles: bufferedFiles,
            deltaSize: bufferedBytes,
            currentPath: currentPath,
            category: category
        ))
        bufferedFiles = 0
        bufferedBytes = 0
    }
}

/// Bridges the synchronous, blocking directory walks off the Swift
/// cooperative thread pool and bounds how many run at once.
///
/// Why this exists: `scanDirectory` / `scanForLargeFiles` are synchronous and
/// never suspend — they sit in a tight loop of blocking syscalls
/// (`enumerator.nextObject()`, `resourceValues(forKeys:)`). Running them
/// directly inside `withTaskGroup` pins one cooperative thread per task for
/// the walk's entire multi-second duration. The cooperative pool is capped
/// near the core count, so ~22 scan targets (times the number of mounted
/// volumes, since `ScanViewModel` fans out one scanner per volume) exhaust
/// it. Once exhausted the executor cannot schedule anything else, and the
/// progress accumulator's `await MainActor.run { … }` hops queue behind the
/// saturated executor — the UI freezes and the file counter stalls then jumps.
///
/// Fix: run each walk on a dedicated concurrent `DispatchQueue` (never on a
/// cooperative thread) and gate entry with an async counting gate so at most
/// `concurrencyLimit` walks are in flight **process-wide**. The gate is
/// static on purpose: a per-scanner limit would still multiply by volume
/// count, which is the exact oversubscription we're fixing.
///
/// Measured on this machine (11 cores) over 22 real `~/Library` subtrees,
/// 177k files: bounded 2/4/5/8 and unbounded all land at ~1.1-1.3s, because
/// the walk is I/O-bound on APFS metadata rather than CPU-bound. Extra
/// concurrency buys no throughput, so a bounded pool costs nothing while
/// leaving the executor free to run the progress accumulator.
///
/// The bound should not be set too LOW, though: at limit 3 the
/// `ScanPerformanceTests` tree (one large cache subtree plus the whole-home
/// sweep) went from 1.04s to 1.26s, because a tight gate serializes walks
/// that genuinely can overlap. `activeProcessorCount / 2` measured level
/// with pre-change `main` when run alone (1.46-1.57s vs 1.50-1.58s,
/// alternating).
///
/// One testing consequence worth knowing: because this gate is static,
/// suites that scan concurrently share its slots, which inflates any
/// wall-clock assertion made while another scanning suite is running.
/// That is harness contention, not a production regression — in the app
/// there is exactly one scan in flight at a time.
enum BlockingScanExecutor {
    /// At most this many blocking walks run concurrently across the whole
    /// process. Half the core count leaves ample cooperative threads for the
    /// progress accumulator and MainActor work without throttling the I/O
    /// overlap the walks legitimately benefit from. Clamped to at least 2 so
    /// single/dual-core machines still overlap some I/O.
    static let concurrencyLimit: Int = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

    /// Dedicated queue for blocking filesystem enumeration. `.utility` keeps
    /// the walks below UI priority; `.concurrent` lets up to
    /// `concurrencyLimit` of them overlap.
    private static let queue = DispatchQueue(
        label: "com.macsift.diskscanner.blocking",
        qos: .utility,
        attributes: .concurrent
    )

    /// Async counting gate. Deliberately NOT a `DispatchSemaphore`: waiting on
    /// a semaphore would block whichever thread called `wait()`. Blocking a
    /// cooperative thread is the bug we're fixing, and blocking a queue thread
    /// would hold one thread per queued walk. An actor-based gate makes
    /// over-limit callers *suspend* instead, so no thread is parked while
    /// waiting for a slot.
    private actor Gate {
        private let limit: Int
        private var active = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) { self.limit = limit }

        func acquire() async {
            if active < limit {
                active += 1
                return
            }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            if let next = waiters.first {
                waiters.removeFirst()
                // Hand the slot straight to the waiter: `active` stays put.
                next.resume()
            } else {
                active -= 1
            }
        }
    }

    private static let gate = Gate(limit: concurrencyLimit)

    /// Total seconds callers have spent SUSPENDED waiting for a gate slot.
    /// Diagnostics only — nothing in production reads it.
    ///
    /// It exists because the gate is process-wide, so when several scans run
    /// concurrently (most visibly under a parallel test runner) a scan's
    /// wall-clock time includes time it spent queued behind unrelated scans.
    /// A perf budget measured on wall-clock would then be measuring
    /// contention rather than scan cost. Subtracting this lets a test assert
    /// on the work itself. See `ScanPerformanceTests`.
    nonisolated(unsafe) private static var _gateWaitSeconds: Double = 0
    private static let gateWaitLock = NSLock()

    static var gateWaitSeconds: Double {
        gateWaitLock.lock()
        defer { gateWaitLock.unlock() }
        return _gateWaitSeconds
    }

    private static func addGateWait(_ seconds: Double) {
        gateWaitLock.lock()
        _gateWaitSeconds += seconds
        gateWaitLock.unlock()
    }

    /// Cancellation flag handed to a blocking walk.
    ///
    /// This is necessary because Swift task-local state does NOT cross a
    /// `DispatchQueue.async` boundary: inside the dispatched block,
    /// `Task.isCancelled` always reads `false` no matter what happened to the
    /// awaiting Task. (Verified directly — without this flag a cancelled scan
    /// enumerated all 20k files instead of bailing out.) So we bridge
    /// cancellation explicitly: `withTaskCancellationHandler` flips this flag,
    /// and the walk polls it on the same every-~200-iterations cadence it
    /// previously used for `Task.isCancelled`.
    final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    /// Run a blocking scan closure off the cooperative pool, waiting for a
    /// slot in the process-wide gate first.
    ///
    /// Cancellation stays cooperative: the walk receives a `CancellationFlag`,
    /// polls it periodically, and returns a partial `ScanRootResult`. The
    /// continuation is therefore always resumed exactly once, and the
    /// semaphore slot is always released.
    static func run(
        _ work: @escaping @Sendable (CancellationFlag) -> ScanRootResult
    ) async -> ScanRootResult {
        // Fast path for an already-cancelled scan: don't even take a slot.
        if Task.isCancelled {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }
        let waitStart = ContinuousClock.now
        await gate.acquire()
        let waited = waitStart.duration(to: .now).components
        addGateWait(Double(waited.seconds) + Double(waited.attoseconds) * 1e-18)
        defer { Task { await gate.release() } }

        let flag = CancellationFlag()
        return await withTaskCancellationHandler {
            // Re-check after acquiring the slot: cancellation may have landed
            // while we were suspended waiting on the gate.
            if Task.isCancelled { flag.cancel() }
            return await withCheckedContinuation { (continuation: CheckedContinuation<ScanRootResult, Never>) in
                queue.async {
                    continuation.resume(returning: work(flag))
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }
}

/// What kind of volume we're scanning. Drives which scan targets run.
enum ScanMode: Sendable {
    /// Boot volume — full pipeline: Library/Caches, Logs, Xcode, dev caches,
    /// Downloads, Mail Downloads, plus the whole-home large-file sweep.
    case boot
    /// External / secondary volume — no ~/Library, no dev caches. Runs only
    /// the whole-volume large-file sweep so the user sees what's eating
    /// space without drowning in irrelevant categories.
    case externalVolume
    /// Demo / screenshot mode. Same category pipeline as `.boot`, but every
    /// root is resolved *relative to `homeDirectory`* — `/tmp` and
    /// `/private/var/log` are deliberately omitted because they are absolute
    /// and would reach outside the sandbox root. Used to populate the window
    /// with disposable fixture data for documentation screenshots without
    /// touching the real home directory.
    case demo
}

struct DiskScanner: Sendable {
    /// Upper bound on the number of unreadable paths each scan task keeps.
    /// A full listing could grow to millions on a locked-down volume; the
    /// UI only needs a representative sample.
    static let inaccessiblePathCap = 50

    let classifier: CategoryClassifier
    let exclusionManager: ExclusionManager
    let homeDirectory: URL
    let maxDepth: Int
    let mode: ScanMode
    /// Volume id stamped onto every ScannedFile produced by this scanner.
    /// The ViewModel uses it to group results per volume in the UI.
    let volumeID: String

    init(
        classifier: CategoryClassifier,
        exclusionManager: ExclusionManager,
        homeDirectory: URL? = nil,
        maxDepth: Int = 20,
        mode: ScanMode = .boot,
        volumeID: String = Volume.bootVolumeID
    ) {
        self.classifier = classifier
        self.exclusionManager = exclusionManager
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.maxDepth = maxDepth
        self.mode = mode
        self.volumeID = volumeID
    }

    /// Run a scan and emit progress to the supplied continuation. Cancellation
    /// is honored via Task cancellation — pass nil for the continuation if you
    /// don't need progress events.
    func scan(progress: AsyncStream<ScanProgress>.Continuation? = nil) async -> ScanResult {
        let startTime = Date()

        // Snapshot exclusions once at the start (avoids hot-loop hops to MainActor)
        let excludedPaths: [String] = await MainActor.run {
            exclusionManager.excludedPaths.map { $0.path(percentEncoded: false) }
        }

        let scanTargets: [(URL, FileCategory?)]
        switch mode {
        case .boot:
            scanTargets = [
                (homeDirectory.appending(path: "Library/Caches"), .cache),
                (homeDirectory.appending(path: "Library/Logs"), .logs),
                (homeDirectory.appending(path: "Library/Application Support"), nil),
                (URL(filePath: "/private/var/log"), .logs),
                (URL(filePath: "/tmp"), .tempFiles),
                (homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData"), .xcodeJunk),
                (homeDirectory.appending(path: "Library/Developer/Xcode/Archives"), .xcodeJunk),
                (homeDirectory.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"), .xcodeJunk),
                (homeDirectory.appending(path: "Library/Developer/CoreSimulator/Caches"), .xcodeJunk),
                (homeDirectory.appending(path: ".npm"), .devCaches),
                (homeDirectory.appending(path: ".yarn"), .devCaches),
                (homeDirectory.appending(path: ".pnpm-store"), .devCaches),
                (homeDirectory.appending(path: ".cache"), .devCaches),
                (homeDirectory.appending(path: ".cargo/registry/cache"), .devCaches),
                (homeDirectory.appending(path: ".rustup/toolchains"), .devCaches),
                (homeDirectory.appending(path: "go/pkg/mod"), .devCaches),
                (homeDirectory.appending(path: "Library/Caches/Homebrew"), .devCaches),
                (homeDirectory.appending(path: "Downloads"), nil),
                (homeDirectory.appending(path: "Library/Mail Downloads"), .mailDownloads),
                (homeDirectory.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"), .mailDownloads),
            ]
        case .demo:
            // Mirrors `.boot` minus the two absolute roots (/tmp and
            // /private/var/log), so a demo scan can never escape the
            // sandbox root it was pointed at.
            scanTargets = [
                (homeDirectory.appending(path: "Library/Caches"), .cache),
                (homeDirectory.appending(path: "Library/Logs"), .logs),
                (homeDirectory.appending(path: "Library/Application Support"), nil),
                (homeDirectory.appending(path: "tmp"), .tempFiles),
                (homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData"), .xcodeJunk),
                (homeDirectory.appending(path: "Library/Developer/CoreSimulator/Caches"), .xcodeJunk),
                (homeDirectory.appending(path: ".npm"), .devCaches),
                (homeDirectory.appending(path: ".cache"), .devCaches),
                (homeDirectory.appending(path: "Downloads"), nil),
                (homeDirectory.appending(path: "Library/Mail Downloads"), .mailDownloads),
            ]
        case .externalVolume:
            // External/secondary volumes only get the large-file sweep — no
            // ~/Library, no /tmp, no dev caches. The sweep walks homeDirectory
            // (which is the volume root) and classifies everything as .largeFiles.
            scanTargets = []
        }

        let classifier = self.classifier
        let maxDepth = self.maxDepth
        let homeDirectory = self.homeDirectory
        let volumeID = self.volumeID

        var allFiles: [FileCategory: [ScannedFile]] = [:]
        var totalInaccessible = 0
        var sampledInaccessiblePaths: [String] = []

        await withTaskGroup(of: ScanRootResult.self) { group in
            // Each walk is dispatched through `BlockingScanExecutor`, which
            // moves the blocking enumeration off the cooperative pool and
            // caps how many run at once process-wide. The task group still
            // drives the fan-out and result aggregation exactly as before —
            // only where the blocking work *executes* has changed.
            for (url, hintCategory) in scanTargets {
                group.addTask {
                    await BlockingScanExecutor.run { cancelFlag in
                        Self.scanDirectory(
                            url,
                            hintCategory: hintCategory,
                            classifier: classifier,
                            excludedPaths: excludedPaths,
                            maxDepth: maxDepth,
                            progress: progress,
                            volumeID: volumeID,
                            cancelFlag: cancelFlag
                        )
                    }
                }
            }

            group.addTask {
                await BlockingScanExecutor.run { cancelFlag in
                    Self.scanForLargeFiles(
                        in: homeDirectory,
                        classifier: classifier,
                        excludedPaths: excludedPaths,
                        progress: progress,
                        volumeID: volumeID,
                        mode: mode,
                        cancelFlag: cancelFlag
                    )
                }
            }

            for await root in group {
                totalInaccessible += root.inaccessibleCount
                for file in root.files {
                    allFiles[file.category, default: []].append(file)
                }
                // Cap the aggregated sample so pathological cases (a whole
                // volume worth of unreadable items) don't bloat the result.
                for path in root.inaccessiblePaths {
                    if sampledInaccessiblePaths.count >= Self.inaccessiblePathCap { break }
                    sampledInaccessiblePaths.append(path)
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        // NOTE: we deliberately do NOT call `progress?.finish()` here.
        // The continuation is owned by the caller — in the multi-volume
        // flow, several scanners share the same continuation and the
        // first one to finish would otherwise close the stream and
        // silently drop every subsequent volume's progress events. The
        // caller runs `defer { continuation.finish() }` around the
        // whole scan fan-out and closes it exactly once.

        return ScanResult(
            filesByCategory: allFiles,
            scanDuration: duration,
            inaccessibleCount: totalInaccessible,
            inaccessiblePaths: sampledInaccessiblePaths
        )
    }

    private static func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
        let path = url.path(percentEncoded: false)
        return excludedPaths.contains { excluded in
            path == excluded || path.hasPrefix(excluded + "/")
        }
    }

    private static func scanDirectory(
        _ directory: URL,
        hintCategory: FileCategory?,
        classifier: CategoryClassifier,
        excludedPaths: [String],
        maxDepth: Int,
        progress: AsyncStream<ScanProgress>.Continuation?,
        volumeID: String,
        cancelFlag: BlockingScanExecutor.CancellationFlag
    ) -> ScanRootResult {
        let fm = FileManager.default

        if isExcluded(directory, excludedPaths: excludedPaths) {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }
        guard fm.isReadableFile(atPath: directory.path(percentEncoded: false)) else {
            // Root itself is unreadable — count it as one inaccessible item
            return ScanRootResult(
                files: [],
                inaccessibleCount: 1,
                inaccessiblePaths: [directory.path(percentEncoded: false)]
            )
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        // Hoisted out of the per-file loop below. Building this Set from the
        // array on every file allocated and re-hashed 4 elements per entry;
        // on a cold cache over 177k real files that measured 4.33s vs 1.25s
        // with the Set built once. Easily the biggest single win here.
        let keySet = Set(keys)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return ScanRootResult(
                files: [],
                inaccessibleCount: 1,
                inaccessiblePaths: [directory.path(percentEncoded: false)]
            )
        }

        var files: [ScannedFile] = []
        var inaccessible = 0
        var inaccessiblePaths: [String] = []
        var throttler = ProgressThrottler(threshold: 100, category: hintCategory, continuation: progress)

        var cancelCheckCounter = 0
        while let next = enumerator.nextObject() {
            // Cooperative cancellation: bail out cleanly if the surrounding
            // Task was cancelled. Check periodically to avoid syscall overhead.
            cancelCheckCounter += 1
            // NOTE: must be `cancelFlag`, not `Task.isCancelled` — this runs
            // on a DispatchQueue where task-local cancellation is invisible.
            if cancelCheckCounter % 200 == 0 && cancelFlag.isCancelled {
                return ScanRootResult(
                    files: files,
                    inaccessibleCount: inaccessible,
                    inaccessiblePaths: inaccessiblePaths
                )
            }
            guard let fileURL = next as? URL else { continue }

            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if isExcluded(fileURL, excludedPaths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: keySet) else {
                inaccessible += 1
                if inaccessiblePaths.count < Self.inaccessiblePathCap {
                    inaccessiblePaths.append(fileURL.path(percentEncoded: false))
                }
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate ?? .distantPast

            let category: FileCategory
            if let hint = hintCategory {
                category = hint
            } else if let classified = classifier.classify(url: fileURL, size: size, modificationDate: modDate) {
                category = classified
            } else {
                continue
            }

            let description = FileDescriptions.describe(url: fileURL, category: category)

            files.append(ScannedFile(
                url: fileURL,
                size: size,
                category: category,
                description: description,
                modificationDate: modDate,
                isDirectory: false,
                volumeID: volumeID
            ))
            throttler.add(bytes: size, currentPath: fileURL.lastPathComponent)
        }

        throttler.flush(currentPath: directory.lastPathComponent)

        return ScanRootResult(
            files: files,
            inaccessibleCount: inaccessible,
            inaccessiblePaths: inaccessiblePaths
        )
    }

    private static func scanForLargeFiles(
        in directory: URL,
        classifier: CategoryClassifier,
        excludedPaths: [String],
        progress: AsyncStream<ScanProgress>.Continuation?,
        volumeID: String,
        mode: ScanMode,
        cancelFlag: BlockingScanExecutor.CancellationFlag
    ) -> ScanRootResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        // Hoisted out of the per-file loop — see the note in `scanDirectory`.
        let keySet = Set(keys)

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ScanRootResult(
                files: [],
                inaccessibleCount: 1,
                inaccessiblePaths: [directory.path(percentEncoded: false)]
            )
        }

        // The skip list is MODE-DEPENDENT, and that is the whole point.
        //
        // Two different reasons to skip a directory are mixed together here:
        //
        //   (a) "another scan target already covers it" — Library/,
        //       Downloads/, and the package-manager caches. Skipping avoids
        //       double-counting the same file under two categories.
        //   (b) "it's build/VCS noise worth no one's attention" —
        //       node_modules, .git, DerivedData, venv, __pycache__, …
        //
        // Reason (a) only holds on the BOOT volume, where `scanTargets`
        // actually contains those roots. In `.externalVolume` mode
        // `scanTargets` is empty and this sweep is the ONLY thing that runs,
        // so applying the (a) entries there skipped directories that nothing
        // else scanned: a user with 500 GB under /Volumes/Backup/Library/ saw
        // an empty result with no indication anything had been omitted. A
        // silent false negative is worse than over-reporting for an app whose
        // core promise is transparency, so the (a) entries are boot-only.
        //
        // Reason (b) applies on every volume — build artifacts are noise
        // wherever they live, and they're also where the "millions of tiny
        // files" cost lives.
        let noiseSkipPrefixes = [
            ".Trash",
            "node_modules",
            ".git",
            "Pods",
            "DerivedData",
            ".build",
            ".next",
            ".nuxt",
            "venv",
            ".venv",
            "__pycache__",
        ]
        let ownedByOtherTargetPrefixes = [
            "Library/",
            "Downloads/",
            ".cache",
            ".cargo",
            ".rustup",
            ".npm",
            ".pnpm-store",
            ".yarn",
            "go/pkg/mod",
        ]
        let skipPrefixes = mode == .boot
            ? noiseSkipPrefixes + ownedByOtherTargetPrefixes
            : noiseSkipPrefixes

        let noiseSkipNames: Set<String> = [
            "node_modules", ".git", "Pods", "DerivedData",
            ".build", ".next", ".nuxt", "venv", ".venv", "__pycache__",
            ".Trash",
        ]
        let ownedByOtherTargetNames: Set<String> = [
            ".cache", ".npm", ".pnpm-store", ".yarn",
        ]
        let skipNames: Set<String> = mode == .boot
            ? noiseSkipNames.union(ownedByOtherTargetNames)
            : noiseSkipNames
        let homePath = directory.path(percentEncoded: false)
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        // SECOND accepted prefix, because the URL APIs and the enumerator can
        // disagree about the same directory. `FileManager.temporaryDirectory`
        // reports `/var/folders/…` and neither `resolvingSymlinksInPath()` nor
        // `realpath(3)` rewrites it, yet the enumerator emits the resolved
        // `/private/var/folders/…` for every entry inside it. Firmlinked and
        // symlinked roots behave the same way.
        //
        // That matters because every entry in `skipPrefixes` is RELATIVE. When
        // the strip below fails, `relativePath` falls back to the absolute
        // path, no relative prefix can ever match, and the entire skip list
        // goes inert — silently. It is not a crash and not a wrong number;
        // the sweep just quietly walks directories it was told to skip.
        // Production is mostly safe (`homeDirectoryForCurrentUser` is
        // canonical) but `startScan(folder:)` feeds a user-supplied URL
        // straight in, so a dropped folder behind a symlink hits this.
        //
        // Deriving the alternate prefix from the enumerator's own first entry
        // is deliberate: it needs no guess about WHICH canonicalization macOS
        // picked, it just adopts whatever the enumerator is actually using.
        // Ask the filesystem for the root's canonical path rather than
        // guessing: `.canonicalPath` is resolved by the same machinery the
        // enumerator uses, so it yields `/private/var/…` where the URL APIs
        // still report `/var/…`.
        let resolvedHomePrefix: String? = {
            guard let canonical = try? directory.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
                  canonical != homePath
            else { return nil }
            return canonical.hasSuffix("/") ? canonical : canonical + "/"
        }()

        /// Strip whichever root prefix the enumerator is reporting. Returns
        /// nil when neither matches, which the caller treats as "the skip
        /// list cannot be trusted for this entry" rather than "skip nothing".
        func relativize(_ filePath: String) -> String? {
            if filePath.hasPrefix(homePrefix) {
                return String(filePath.dropFirst(homePrefix.count))
            }
            if let resolvedHomePrefix, filePath.hasPrefix(resolvedHomePrefix) {
                return String(filePath.dropFirst(resolvedHomePrefix.count))
            }
            return nil
        }
        var files: [ScannedFile] = []
        var inaccessible = 0
        var inaccessiblePaths: [String] = []
        // Large-file scan walks many small files between hits, so we ask the
        // throttler to flush on a visited-count cadence (threshold 1 means
        // any buffered delta goes out at the next tick).
        var throttler = ProgressThrottler(threshold: 1, category: .largeFiles, continuation: progress)
        var visited = 0

        while let next = enumerator.nextObject() {
            // See the note in `scanDirectory`: `Task.isCancelled` does not
            // cross the Dispatch hop, so poll the explicit flag.
            if visited % 200 == 0 && cancelFlag.isCancelled {
                return ScanRootResult(
                    files: files,
                    inaccessibleCount: inaccessible,
                    inaccessiblePaths: inaccessiblePaths
                )
            }
            guard let fileURL = next as? URL else { continue }

            visited += 1
            if visited % 500 == 0 {
                throttler.flush(currentPath: fileURL.lastPathComponent)
            }

            let filePath = fileURL.path(percentEncoded: false)
            let relativePath = relativize(filePath)

            // Quick name-based skip (avoids prefix walk for common cases)
            let lastComponent = fileURL.lastPathComponent
            if skipNames.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            // When the path can't be made relative to the scan root, the
            // relative skip list is meaningless for this entry. Fall back to
            // matching against the ABSOLUTE path: a skip entry like
            // "node_modules" or ".git" still matches as a path component, so
            // noise stays skipped instead of the list silently going inert.
            let skipCandidate = relativePath ?? filePath
            if skipPrefixes.contains(where: { skipCandidate.hasPrefix($0) })
                || (relativePath == nil && skipPrefixes.contains(where: { skipCandidate.contains("/" + $0) }))
            {
                enumerator.skipDescendants()
                continue
            }

            if isExcluded(fileURL, excludedPaths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: keySet) else {
                inaccessible += 1
                if inaccessiblePaths.count < Self.inaccessiblePathCap {
                    inaccessiblePaths.append(fileURL.path(percentEncoded: false))
                }
                continue
            }

            if values.isSymbolicLink == true || values.isDirectory == true { continue }

            let size = Int64(values.fileSize ?? 0)
            guard size > classifier.largeFileThresholdBytes else { continue }

            let modDate = values.contentModificationDate ?? .distantPast
            let description = FileDescriptions.describe(url: fileURL, category: .largeFiles)

            files.append(ScannedFile(
                url: fileURL,
                size: size,
                category: .largeFiles,
                description: description,
                modificationDate: modDate,
                isDirectory: false,
                volumeID: volumeID
            ))
            throttler.add(bytes: size, currentPath: fileURL.lastPathComponent)
        }

        throttler.flush(currentPath: directory.lastPathComponent)

        return ScanRootResult(
            files: files,
            inaccessibleCount: inaccessible,
            inaccessiblePaths: inaccessiblePaths
        )
    }
}
