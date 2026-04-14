import Foundation

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

    private static func isProtectedPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        for prefix in neverDeletePrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") { return true }
        }
        return false
    }

    /// Clean the supplied files. Progress events are emitted to the supplied
    /// continuation (pass nil if you don't care). The continuation is NOT
    /// finished by this function — the caller owns its lifecycle.
    func clean(
        files: [ScannedFile],
        dryRun: Bool,
        progress: AsyncStream<CleaningProgress>.Continuation? = nil
    ) async -> CleaningReport {
        var deletedCount = 0
        var freedSize: Int64 = 0
        var failedFiles: [(ScannedFile, String)] = []
        var firstTrashDestination: URL?

        for (index, file) in files.enumerated() {
            progress?.yield(CleaningProgress(
                processed: index + 1,
                total: files.count,
                currentFile: file.name,
                freedSoFar: freedSize
            ))

            let outcome: CleaningOutcome
            if dryRun {
                outcome = .deleted(bytes: file.size, trashDestination: nil)
            } else if file.category == .timeMachineSnapshots {
                outcome = await Self.cleanTimeMachineSnapshot(file)
            } else {
                outcome = Self.cleanFile(file)
            }

            switch outcome {
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

        return CleaningReport(
            deletedCount: deletedCount,
            freedSize: freedSize,
            failedFiles: failedFiles,
            totalProcessed: files.count,
            firstTrashDestination: firstTrashDestination
        )
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
