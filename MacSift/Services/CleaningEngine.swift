import Foundation
import AppKit

struct CleaningReport: Sendable {
    let deletedCount: Int
    let freedSize: Int64
    let failedFiles: [(ScannedFile, String)]
    let totalProcessed: Int
    /// Where the first successfully trashed file landed. Surfaced in the
    /// MacSift log and on the success screen so the user can verify that
    /// `trashItem` actually moved the file into the user's Trash folder
    /// rather than silently hard-deleting it. Nil on dry run or when no
    /// file was successfully trashed.
    let firstTrashDestination: URL?

    var successRate: Double {
        guard totalProcessed > 0 else { return 1.0 }
        return Double(deletedCount) / Double(totalProcessed)
    }
}

struct CleaningProgress: Sendable {
    let processed: Int
    let total: Int
    let currentFile: String
    let freedSoFar: Int64
}

/// Per-file outcome from an attempted cleaning. The caller (`clean`) folds
/// these into the final `CleaningReport`.
private enum CleaningOutcome {
    case deleted(bytes: Int64, trashDestination: URL?)
    case failed(reason: String)
    case missing
}

struct CleaningEngine: Sendable {
    /// System paths we NEVER delete, no matter what the scanner surfaces.
    /// Checked as a prefix match — anything starting with `/System/...` is
    /// blocked, not just `/System` itself.
    private static let neverDeletePrefixes: Set<String> = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
    ]

    /// Folder/file names that live at the root of ANY mounted volume and
    /// serve system bookkeeping (Spotlight, FSEvents, per-volume Trash,
    /// Time Machine backups). Trashing them on an external drive breaks
    /// indexing and backups — always hard-block regardless of category.
    private static let protectedVolumeRootNames: Set<String> = [
        ".Spotlight-V100",
        ".fseventsd",
        ".Trashes",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        "Backups.backupdb",
        ".HFS+ Private Directory Data\u{000d}",
    ]

    /// Defense in depth: strip `..`, double-slashes, trailing slashes, and
    /// any `/./` segments before doing prefix matching. The canonical
    /// input already comes from `FileManager.enumerator` and should
    /// arrive clean, but a bug elsewhere (or a future caller with
    /// attacker-controlled input) shouldn't silently bypass the
    /// never-delete list just because the path string has an extra slash.
    private static func normalize(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
    }

    private static func isProtectedPath(_ rawPath: String) -> Bool {
        let path = normalize(rawPath)
        guard path.hasPrefix("/") else { return false }
        for prefix in neverDeletePrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        // Any path containing a protected volume-root name as a segment is
        // blocked. Covers both `/Volumes/T7/.Spotlight-V100/...` and the
        // root folder itself.
        for segment in path.split(separator: "/") {
            if protectedVolumeRootNames.contains(String(segment)) { return true }
        }
        return false
    }

    /// How many files get trashed together in a single NSWorkspace.recycle
    /// call. Tuned empirically: Finder's XPC round-trip has meaningful
    /// fixed overhead, so batching amortizes it. Too large and the user
    /// waits too long between progress updates; too small and we're back
    /// to the per-file round-trip cost. 500 feels right on Tahoe.
    private static let trashBatchSize = 500

    /// Clean the supplied files. Progress events are emitted to the supplied
    /// continuation (pass nil if you don't care). The continuation is NOT
    /// finished by this function — the caller owns its lifecycle.
    ///
    /// Performance: regular files are trashed in batches of 500 via
    /// `NSWorkspace.recycle` so the per-file Finder XPC overhead is
    /// amortized across the whole batch. Earlier versions called
    /// `FileManager.trashItem` in a tight loop, which took a minute-plus
    /// for thousands of cache files. The batch API completes the same
    /// work in a couple of seconds.
    func clean(
        files: [ScannedFile],
        dryRun: Bool,
        progress: AsyncStream<CleaningProgress>.Continuation? = nil
    ) async -> CleaningReport {
        var deletedCount = 0
        var freedSize: Int64 = 0
        var failedFiles: [(ScannedFile, String)] = []
        var firstTrashDestination: URL?
        var processed = 0
        let total = files.count

        // Dry run short-circuit: no disk work, just fold the totals and
        // emit a progress event per file so the preview UI stays live.
        // Per-file yields are cheap here — no disk, no XPC, just struct
        // allocation — so there's no reason to throttle.
        if dryRun {
            for (index, file) in files.enumerated() {
                deletedCount += 1
                freedSize += file.size
                progress?.yield(CleaningProgress(
                    processed: index + 1,
                    total: total,
                    currentFile: file.name,
                    freedSoFar: freedSize
                ))
            }
            return CleaningReport(
                deletedCount: deletedCount,
                freedSize: freedSize,
                failedFiles: failedFiles,
                totalProcessed: total,
                firstTrashDestination: nil
            )
        }

        // Partition by category: Time Machine snapshots go through tmutil
        // (one at a time), everything else gets batched.
        var snapshots: [ScannedFile] = []
        var regular: [ScannedFile] = []
        snapshots.reserveCapacity(16)
        regular.reserveCapacity(files.count)
        for file in files {
            if file.category == .timeMachineSnapshots {
                snapshots.append(file)
            } else {
                regular.append(file)
            }
        }

        // --- Snapshots: one tmutil call per entry (rare, usually <10).
        for file in snapshots {
            processed += 1
            progress?.yield(CleaningProgress(
                processed: processed,
                total: total,
                currentFile: file.name,
                freedSoFar: freedSize
            ))
            switch await Self.cleanTimeMachineSnapshot(file) {
            case .deleted(let bytes, _):
                deletedCount += 1
                freedSize += bytes
            case .failed(let reason):
                failedFiles.append((file, reason))
            case .missing:
                continue
            }
        }

        // --- Regular files: split into batches and recycle each batch.
        // Protected paths are filtered out BEFORE the batch so
        // NSWorkspace.recycle never touches system-critical locations.
        let fm = FileManager.default
        var chunkStart = 0
        while chunkStart < regular.count {
            let chunkEnd = min(chunkStart + Self.trashBatchSize, regular.count)
            let chunk = Array(regular[chunkStart..<chunkEnd])
            chunkStart = chunkEnd

            var chunkURLs: [URL] = []
            chunkURLs.reserveCapacity(chunk.count)
            var fileByPath: [String: ScannedFile] = [:]
            fileByPath.reserveCapacity(chunk.count)

            for file in chunk {
                let path = file.url.path(percentEncoded: false)
                if Self.isProtectedPath(path) {
                    failedFiles.append((file, "System file — deletion blocked for safety"))
                    processed += 1
                    continue
                }
                guard fm.fileExists(atPath: path) else {
                    // Already gone (trashed in a prior pass, user moved
                    // it, etc.) — count as processed but not deleted.
                    processed += 1
                    continue
                }
                chunkURLs.append(file.url)
                fileByPath[path] = file
            }

            if chunkURLs.isEmpty { continue }

            let trashed = await Self.recycleBatch(chunkURLs)

            // Fold the successes into totals.
            for (source, destination) in trashed {
                let sourcePath = source.path(percentEncoded: false)
                guard let file = fileByPath.removeValue(forKey: sourcePath) else { continue }
                deletedCount += 1
                freedSize += file.size
                processed += 1
                if firstTrashDestination == nil {
                    firstTrashDestination = destination
                }
            }

            // Anything left in fileByPath wasn't in the `trashed`
            // dictionary — the batch API couldn't move it. Retry
            // individually so we can surface a friendly per-file error
            // message (locked cache DB, permission denied, etc.).
            for (_, file) in fileByPath {
                processed += 1
                switch Self.cleanFile(file) {
                case .deleted(let bytes, let destination):
                    deletedCount += 1
                    freedSize += bytes
                    if firstTrashDestination == nil, let destination {
                        firstTrashDestination = destination
                    }
                case .failed(let reason):
                    failedFiles.append((file, reason))
                case .missing:
                    continue
                }
            }

            progress?.yield(CleaningProgress(
                processed: processed,
                total: total,
                currentFile: chunk.last?.name ?? "",
                freedSoFar: freedSize
            ))
        }

        return CleaningReport(
            deletedCount: deletedCount,
            freedSize: freedSize,
            failedFiles: failedFiles,
            totalProcessed: total,
            firstTrashDestination: firstTrashDestination
        )
    }

    /// Wrap `NSWorkspace.recycle` in an async call. The returned
    /// dictionary maps the original URL to the new location in the Trash
    /// for every file that was successfully moved. Files not present in
    /// the dictionary either failed or were skipped — the caller is
    /// responsible for figuring out which.
    private static func recycleBatch(_ urls: [URL]) async -> [URL: URL] {
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { trashed, _ in
                continuation.resume(returning: trashed)
            }
        }
    }

    /// Move a single file to the user's Trash. Returns the outcome — caller
    /// is responsible for folding it into the aggregate report.
    private static func cleanFile(_ file: ScannedFile) -> CleaningOutcome {
        let path = file.url.path(percentEncoded: false)

        if isProtectedPath(path) {
            return .failed(reason: "System file — deletion blocked for safety")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return .missing }

        do {
            var resultingURL: NSURL?
            try fm.trashItem(at: file.url, resultingItemURL: &resultingURL)
            return .deleted(bytes: file.size, trashDestination: resultingURL as URL?)
        } catch {
            return .failed(reason: friendlyTrashError(for: file, underlying: error))
        }
    }

    /// Translate `trashItem` failures into something the user can act on.
    /// The macOS default message is "you don't have permission to access
    /// it", which is misleading for SQLite cache DBs held open by a running
    /// process — the real issue is that the owning app has a file lock and
    /// needs to be quit before the file becomes trashable.
    private static func friendlyTrashError(for file: ScannedFile, underlying: Error) -> String {
        let fallback = underlying.localizedDescription
        let name = file.url.lastPathComponent.lowercased()
        let isLikelyLocked = name == "cache.db"
            || name.hasPrefix("cache.db-")
            || name.hasSuffix(".sqlite")
            || name.hasSuffix(".sqlite-wal")
            || name.hasSuffix(".sqlite-shm")
        guard isLikelyLocked else { return fallback }

        // Walk the path for a `Library/Caches/<bundle-id>/` segment so we
        // can name the owning app. Falls back to a generic message if the
        // file isn't under a standard cache folder.
        let components = file.url.pathComponents
        if let cachesIndex = components.firstIndex(of: "Caches"),
           components.count > cachesIndex + 1 {
            let ownerKey = components[cachesIndex + 1]
            let label = BundleNames.humanLabel(for: ownerKey)
            return "\(label) is running and has this file locked. Quit \(label) and rescan."
        }
        return "The owning app is running and has this file locked. Quit it and rescan."
    }

    /// Time Machine snapshots have a synthetic URL; dispatch to `tmutil`
    /// via `TimeMachineService` and translate permission errors into a hint
    /// pointing the user at the sudo form.
    private static func cleanTimeMachineSnapshot(_ file: ScannedFile) async -> CleaningOutcome {
        let dateString = String(
            file.url.lastPathComponent
                .dropFirst("com.apple.TimeMachine.".count)
                .dropLast(".local".count)
        )
        do {
            try await TimeMachineService.deleteSnapshot(dateString: dateString)
            return .deleted(bytes: file.size, trashDestination: nil)
        } catch {
            let msg = error.localizedDescription
            let hint = msg.contains("not permitted") || msg.contains("requires") || msg.contains("must be run")
                ? "Requires admin privileges. Run `sudo tmutil deletelocalsnapshots \(dateString)` in Terminal."
                : msg
            return .failed(reason: hint)
        }
    }
}
