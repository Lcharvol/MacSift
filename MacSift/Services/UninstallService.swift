import Foundation
import AppKit

/// Coordinates the in-app uninstall flow. Removes everything MacSift has
/// written to disk (settings, logs, cached update zips) and trashes the
/// running .app bundle itself. Does NOT try to revoke the Full Disk
/// Access grant — that's TCC and the user has to undo it in System
/// Settings themselves.
///
/// The steps are split into small testable helpers so we can exercise
/// the disk-removal logic with temp directories. The `uninstall()` entry
/// point glues them together and is what the UI calls.
enum UninstallService {
    /// Summary of what an uninstall pass actually removed. Returned to the
    /// UI so the "Uninstalled" dialog can tell the user what it did.
    struct Report: Sendable, Equatable {
        var clearedUserDefaults: Bool = false
        var removedLogsAt: URL? = nil
        var removedUpdateArtifacts: Int = 0
        var reclaimedUpdateBytes: Int64 = 0
        var trashedBundleAt: URL? = nil
        var errors: [String] = []
    }

    /// Run the full uninstall pipeline in order, stopping short only if
    /// a step throws — partial progress is still reported in the Report.
    @MainActor
    static func uninstall() async -> Report {
        var report = Report()

        // 1. UserDefaults domain — settings, exclusions, lifetime counters.
        if let bundleID = Bundle.main.bundleIdentifier {
            clearUserDefaults(bundleID: bundleID)
            report.clearedUserDefaults = true
        } else {
            report.errors.append("Could not resolve bundle identifier — settings not cleared")
        }

        // 2. On-disk audit log at ~/Library/Logs/MacSift
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/MacSift")
        if clearLogs(at: logsURL) {
            report.removedLogsAt = logsURL
        }

        // 3. Cached update zips + extraction folders in ~/Downloads.
        //    We ONLY touch entries that match the `MacSift-*` pattern
        //    we created ourselves — never anything else in Downloads.
        let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Downloads")
        let updateSummary = clearDownloadedUpdates(from: downloadsURL)
        report.removedUpdateArtifacts = updateSummary.removedCount
        report.reclaimedUpdateBytes = updateSummary.reclaimedBytes

        // 4. Trash the running .app bundle. We trash rather than hard-
        //    delete so the user can still recover it from Finder if they
        //    change their mind before emptying.
        let bundleURL = Bundle.main.bundleURL
        switch trashAppBundle(at: bundleURL) {
        case .success(let destination):
            report.trashedBundleAt = destination
        case .failure(let message):
            report.errors.append(message)
        }

        return report
    }

    // MARK: - Testable helpers

    /// Wipe every key in MacSift's UserDefaults domain. `removePersistentDomain`
    /// is the canonical API for "forget everything this app ever stored" —
    /// faster and more complete than iterating keys manually.
    static func clearUserDefaults(bundleID: String) {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }

    /// Remove the log folder at the given URL, including every file inside
    /// it. Returns `true` if the folder existed and was removed, `false`
    /// if there was nothing to remove or the removal failed silently.
    static func clearLogs(at url: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        do {
            try fm.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    struct UpdateRemovalSummary: Equatable {
        var removedCount: Int
        var reclaimedBytes: Int64
    }

    /// Walk the given Downloads directory and remove every top-level
    /// entry whose name matches the `MacSift-<version>` or
    /// `MacSift-<version>.zip` pattern we write in `UpdateDownloader`.
    /// Anything else in Downloads is left untouched — we never risk
    /// trashing user files.
    static func clearDownloadedUpdates(from downloadsDir: URL) -> UpdateRemovalSummary {
        var summary = UpdateRemovalSummary(removedCount: 0, reclaimedBytes: 0)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey]
        ) else {
            return summary
        }
        for entry in entries {
            let name = entry.lastPathComponent
            guard looksLikeMacSiftUpdateArtifact(name: name) else { continue }
            summary.reclaimedBytes += sizeOf(url: entry)
            if (try? fm.removeItem(at: entry)) != nil {
                summary.removedCount += 1
            }
        }
        return summary
    }

    /// Strict naming check so we never mistake an unrelated file for an
    /// update artifact. Matches `MacSift-X.Y.Z[-suffix].zip` and the
    /// extracted `MacSift-X.Y.Z[-suffix]` folder, nothing else. No
    /// wildcards, no partial matches — if the name doesn't look exactly
    /// like something we wrote, it stays.
    private static func looksLikeMacSiftUpdateArtifact(name: String) -> Bool {
        let prefix = "MacSift-"
        guard name.hasPrefix(prefix), name.count > prefix.count else { return false }
        var version = name
        version.removeFirst(prefix.count)
        if version.hasSuffix(".zip") { version.removeLast(4) }
        // Version must be a safe string: alphanumerics, `.`, `-`, `_`.
        // Reuses the same allow-list UpdateChecker enforces at download time.
        return UpdateChecker.isSafeVersionString(version)
    }

    /// Recursively sum the allocated size of everything under the URL.
    /// Used only by `clearDownloadedUpdates` for the reclaim-bytes display —
    /// if it fails (permission, IO error) we just report 0 bytes and
    /// continue, rather than aborting the whole uninstall.
    private static func sizeOf(url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            var total: Int64 = 0
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else { return 0 }
            while let next = enumerator.nextObject() as? URL {
                if let v = try? next.resourceValues(forKeys: keys),
                   v.isDirectory != true
                {
                    total += Int64(v.totalFileAllocatedSize ?? 0)
                }
            }
            return total
        }
        return Int64(values.totalFileAllocatedSize ?? 0)
    }

    enum TrashOutcome {
        case success(destination: URL?)
        case failure(String)
    }

    /// Move the given .app bundle to the user's Trash. Safe to call on
    /// the currently-running bundle — macOS lets a process trash its own
    /// .app; the running code keeps executing until `NSApp.terminate`.
    static func trashAppBundle(at bundleURL: URL) -> TrashOutcome {
        let fm = FileManager.default
        do {
            var resultingURL: NSURL?
            try fm.trashItem(at: bundleURL, resultingItemURL: &resultingURL)
            return .success(destination: resultingURL as URL?)
        } catch {
            return .failure("Could not move the app bundle to Trash: \(error.localizedDescription). Drag MacSift.app to the Trash yourself after the app quits.")
        }
    }
}
