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

actor CleaningEngine {
    private static let neverDeletePrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
    ]

    private var progressContinuation: AsyncStream<CleaningProgress>.Continuation?
    private var _progressStream: AsyncStream<CleaningProgress>?

    func progressStream() -> AsyncStream<CleaningProgress> {
        if let existing = _progressStream {
            return existing
        }
        let stream = AsyncStream<CleaningProgress> { continuation in
            self.progressContinuation = continuation
        }
        _progressStream = stream
        return stream
    }

    func clean(files: [ScannedFile], dryRun: Bool) async -> CleaningReport {
        var deletedCount = 0
        var freedSize: Int64 = 0
        var failedFiles: [(ScannedFile, String)] = []
        let fm = FileManager.default

        for (index, file) in files.enumerated() {
            let path = file.url.path(percentEncoded: false)

            if Self.neverDeletePrefixes.contains(where: { path.hasPrefix($0) }) {
                failedFiles.append((file, "System file — deletion blocked for safety"))
                continue
            }

            progressContinuation?.yield(CleaningProgress(
                processed: index + 1,
                total: files.count,
                currentFile: file.name,
                freedSoFar: freedSize
            ))

            if dryRun {
                deletedCount += 1
                freedSize += file.size
                continue
            }

            guard fm.fileExists(atPath: path) else { continue }

            do {
                try fm.removeItem(at: file.url)
                deletedCount += 1
                freedSize += file.size
            } catch {
                failedFiles.append((file, error.localizedDescription))
            }
        }

        progressContinuation?.finish()

        return CleaningReport(
            deletedCount: deletedCount,
            freedSize: freedSize,
            failedFiles: failedFiles,
            totalProcessed: files.count
        )
    }
}
