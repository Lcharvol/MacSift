import Foundation
import os

/// Small append-only log file at `~/Library/Logs/MacSift/macsift.log`.
/// We write every scan summary and every cleaning error here so users can
/// audit what the app did without needing a debugger. The file is trimmed
/// to ~500KB — old entries drop off the front on each write.
///
/// Also mirrored to os_log under subsystem `com.lcharvol.MacSift` so Console
/// shows the same events live.
enum MacSiftLog {
    private static let subsystem = "com.lcharvol.MacSift"
    private static let osLogger = Logger(subsystem: subsystem, category: "app")

    /// Cap the on-disk log at ~500KB. On first write that pushes us over,
    /// we drop the oldest lines until we're back under the cap.
    private static let maxFileBytes = 500 * 1024

    /// Isolated serial queue so concurrent writes don't interleave bytes.
    /// Lazily-created file URL: `~/Library/Logs/MacSift/macsift.log`.
    private static let queue = DispatchQueue(label: "com.lcharvol.MacSift.log")

    private static let logFileURL: URL = {
        let fm = FileManager.default
        let logsRoot = fm.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/MacSift")
        try? fm.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        return logsRoot.appending(path: "macsift.log")
    }()

    // Privacy note: the on-disk log at ~/Library/Logs/MacSift/macsift.log
    // is owned by the user and not world-readable, so it can reasonably
    // contain file paths. But os_log messages are visible to anyone who
    // opens Console.app on the machine, and they're persisted in the
    // unified log for days. We mark those `.private` so file paths don't
    // leak into Console — the on-disk file stays the authoritative
    // (and more permissive) audit trail.

    static func info(_ message: String) {
        osLogger.info("\(message, privacy: .private)")
        append(level: "INFO", message: message)
    }

    static func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .private)")
        append(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        osLogger.error("\(message, privacy: .private)")
        append(level: "ERROR", message: message)
    }

    /// Returns the last N lines of the log, newest first. Used by future
    /// diagnostics UIs; unused today but kept close to the writer so the
    /// two stay in sync.
    static func tail(lines: Int = 100) -> [String] {
        queue.sync {
            guard let data = try? Data(contentsOf: logFileURL),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            let all = text.split(whereSeparator: \.isNewline).map(String.init)
            return Array(all.suffix(lines).reversed())
        }
    }

    private static func append(level: String, message: String) {
        queue.async {
            // Build the formatter per-write. It's cheap and keeps us out of
            // the non-Sendable-static-property trap that Swift 6 flags.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            let line = "\(timestamp) [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let fm = FileManager.default
            if !fm.fileExists(atPath: logFileURL.path(percentEncoded: false)) {
                try? data.write(to: logFileURL)
                return
            }

            // Append, then trim if we've crossed the cap. Trim drops the
            // oldest ~10% so we don't repeatedly rewrite on every line.
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }

            if let size = try? logFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maxFileBytes {
                trimLogFile(dropRatio: 0.1)
            }
        }
    }

    private static func trimLogFile(dropRatio: Double) {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let dropCount = max(1, Int(Double(lines.count) * dropRatio))
        guard dropCount < lines.count else { return }
        let kept = lines.dropFirst(dropCount).joined(separator: "\n") + "\n"
        try? kept.data(using: .utf8)?.write(to: logFileURL)
    }
}

