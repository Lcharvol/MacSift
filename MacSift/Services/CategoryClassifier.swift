import Foundation

struct CategoryClassifier: Sendable {
    let largeFileThresholdBytes: Int64

    init(largeFileThresholdBytes: Int64 = 500 * 1024 * 1024) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
    }

    func classify(url: URL, size: Int64) -> FileCategory? {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let homePrefix = home.hasSuffix("/") ? home : home + "/"

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

        // Large files (anywhere in home)
        if path.hasPrefix(homePrefix) && size > largeFileThresholdBytes {
            return .largeFiles
        }

        return nil
    }
}
