import Foundation

struct CategoryClassifier: Sendable {
    let largeFileThresholdBytes: Int64
    /// Lowercased bundle names of installed apps, e.g. {"safari", "xcode"}.
    /// Used to detect orphaned Application Support folders.
    let installedAppBundleNames: Set<String>

    init(
        largeFileThresholdBytes: Int64 = 500 * 1024 * 1024,
        installedAppBundleNames: Set<String> = Self.scanInstalledAppBundleNames()
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.installedAppBundleNames = installedAppBundleNames
    }

    /// Walks /Applications and ~/Applications once at init and collects the
    /// lowercased bundle base names. Used to flag Application Support folders
    /// whose owner app is no longer installed.
    static func scanInstalledAppBundleNames() -> Set<String> {
        let fm = FileManager.default
        let roots: [URL] = [
            URL(filePath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        var names = Set<String>()
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                let base = entry.deletingPathExtension().lastPathComponent.lowercased()
                names.insert(base)
                // Also store the simplified one-word version for fuzzy matching:
                // "Visual Studio Code" → "vscode" / "code"
                let words = base.split(separator: " ")
                if words.count > 1 {
                    names.insert(words.joined())
                }
                if let last = words.last {
                    names.insert(String(last))
                }
            }
        }
        return names
    }

    /// Returns true if the given Application Support subfolder belongs to an
    /// installed app. The folder name is matched case-insensitively against
    /// the cached set of installed app names.
    func isOrphanedAppSupport(folderName: String) -> Bool {
        let key = folderName.lowercased()
        if installedAppBundleNames.contains(key) { return false }
        // Many apps use reverse-DNS folders like "com.apple.Safari" — match the
        // last segment against installed app names.
        if let lastSegment = key.split(separator: ".").last {
            if installedAppBundleNames.contains(String(lastSegment)) { return false }
        }
        return true
    }

    func classify(url: URL, size: Int64) -> FileCategory? {
        let path = url.path(percentEncoded: false)
        let homePrefix = Self.cachedHomePrefix

        // iOS Backups (check before general appData)
        if path.contains("MobileSync/Backup") {
            return .iosBackups
        }

        // Caches
        if path.hasPrefix("\(homePrefix)Library/Caches") {
            return .cache
        }

        // Logs
        if path.hasPrefix("\(homePrefix)Library/Logs") || path.hasPrefix("/private/var/log") {
            return .logs
        }

        // Temp files
        if path.hasPrefix("/tmp") || path.hasPrefix(NSTemporaryDirectory()) {
            return .tempFiles
        }

        // Application Support: only classify as .appData if the parent folder
        // belongs to an app that is no longer installed (orphaned data).
        let appSupportPrefix = "\(homePrefix)Library/Application Support/"
        if path.hasPrefix(appSupportPrefix) {
            // Extract the first path component after Application Support
            let relative = String(path.dropFirst(appSupportPrefix.count))
            let firstComponent = relative.split(separator: "/").first.map(String.init) ?? ""
            if isOrphanedAppSupport(folderName: firstComponent) {
                return .appData
            } else {
                // Belongs to an installed app — leave it alone
                return nil
            }
        }

        // Large files (anywhere in home)
        if path.hasPrefix(homePrefix) && size > largeFileThresholdBytes {
            return .largeFiles
        }

        return nil
    }

    // Cache the home directory prefix once instead of recomputing on every file
    private static let cachedHomePrefix: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return home.hasSuffix("/") ? home : home + "/"
    }()
}
