import Foundation

struct CleaningReport: Sendable {
    let deletedCount: Int
    let freedSize: Int64
    let failedFiles: [(ScannedFile, String)]
    let totalProcessed: Int

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
    case deleted(bytes: Int64)
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

        for (index, file) in files.enumerated() {
            progress?.yield(CleaningProgress(
                processed: index + 1,
                total: files.count,
                currentFile: file.name,
                freedSoFar: freedSize
            ))

            let outcome: CleaningOutcome
            if dryRun {
                outcome = .deleted(bytes: file.size)
            } else if file.category == .timeMachineSnapshots {
                outcome = await Self.cleanTimeMachineSnapshot(file)
            } else {
                outcome = Self.cleanFile(file)
            }

            switch outcome {
            case .deleted(let bytes):
                deletedCount += 1
                freedSize += bytes
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
            totalProcessed: files.count
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
            return .deleted(bytes: file.size)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
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
            return .deleted(bytes: file.size)
        } catch {
            let msg = error.localizedDescription
            let hint = msg.contains("not permitted") || msg.contains("requires") || msg.contains("must be run")
                ? "Requires admin privileges. Run `sudo tmutil deletelocalsnapshots \(dateString)` in Terminal."
                : msg
            return .failed(reason: hint)
        }
    }
}
