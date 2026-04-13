import Foundation

enum FileDescriptions {
    static func describe(url: URL, category: FileCategory) -> String {
        let name = url.lastPathComponent
        let path = url.path(percentEncoded: false).lowercased()

        switch category {
        case .cache:
            return describeCacheFile(name: name, path: path)
        case .logs:
            return describeLogFile(name: name, path: path)
        case .tempFiles:
            return "Temporary file: \(name)"
        case .appData:
            return "Unused app data: \(name)"
        case .largeFiles:
            return "Large file: \(name)"
        case .timeMachineSnapshots:
            return "Time Machine local snapshot"
        case .iosBackups:
            return describeIOSBackup(url: url)
        case .xcodeJunk:
            if path.contains("deriveddata") { return "Xcode derived data: \(name)" }
            if path.contains("archives") { return "Xcode archive: \(name)" }
            if path.contains("devicesupport") { return "iOS debug symbols: \(name)" }
            if path.contains("coresimulator") { return "Simulator cache: \(name)" }
            return "Xcode junk: \(name)"
        case .devCaches:
            if path.contains(".npm") { return "npm cache: \(name)" }
            if path.contains(".yarn") { return "yarn cache: \(name)" }
            if path.contains(".pnpm") { return "pnpm cache: \(name)" }
            if path.contains("pip") { return "pip cache: \(name)" }
            if path.contains("cargo") { return "Cargo cache: \(name)" }
            if path.contains("rustup") { return "Rust toolchain: \(name)" }
            if path.contains("go/pkg") { return "Go module: \(name)" }
            if path.contains("homebrew") { return "Homebrew download: \(name)" }
            return "Dev cache: \(name)"
        case .oldDownloads:
            return "Old download: \(name)"
        case .mailDownloads:
            return "Mail attachment: \(name)"
        }
    }

    private static func describeCacheFile(name: String, path: String) -> String {
        let knownApps: [(pattern: String, label: String)] = [
            ("safari", "Safari"),
            ("chrome", "Google Chrome"),
            ("firefox", "Firefox"),
            ("slack", "Slack"),
            ("spotify", "Spotify"),
            ("discord", "Discord"),
            ("xcode", "Xcode"),
            ("figma", "Figma"),
        ]

        for app in knownApps {
            if path.contains(app.pattern) || name.lowercased().contains(app.pattern) {
                return "\(app.label) cache"
            }
        }
        return "Application cache: \(name)"
    }

    private static func describeLogFile(name: String, path: String) -> String {
        if path.contains("/private/var/log") {
            return "System log: \(name)"
        }
        return "Application log: \(name)"
    }

    /// Walks up the URL until it finds a backup root (a folder directly under
    /// MobileSync/Backup) and reads its Info.plist for the device name + date.
    /// Cached so repeated lookups for the same backup don't re-read the plist.
    private final class IOSBackupCache: @unchecked Sendable {
        private var dict: [String: String] = [:]
        private let lock = NSLock()
        func get(_ key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return dict[key]
        }
        func set(_ key: String, _ value: String) {
            lock.lock(); defer { lock.unlock() }
            dict[key] = value
        }
    }
    private static let iosBackupCache = IOSBackupCache()

    private static func describeIOSBackup(url: URL) -> String {
        let path = url.path(percentEncoded: false)
        // Find the backup root: the path component immediately after "Backup/"
        guard let backupRange = path.range(of: "MobileSync/Backup/") else {
            return "iOS backup: \(url.lastPathComponent)"
        }
        let afterBackup = path[backupRange.upperBound...]
        guard let firstSlash = afterBackup.firstIndex(of: "/") ?? afterBackup.endIndex as String.Index? else {
            return "iOS backup: \(url.lastPathComponent)"
        }
        let backupID = String(afterBackup[..<firstSlash])
        let backupRootPath = String(path[..<backupRange.upperBound]) + backupID

        if let cached = iosBackupCache.get(backupRootPath) {
            return cached
        }

        let infoPlistURL = URL(filePath: backupRootPath).appending(path: "Info.plist")
        var label = "iOS backup"
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            let deviceName = plist["Device Name"] as? String
            let productType = plist["Product Type"] as? String
            let lastBackupDate = plist["Last Backup Date"] as? Date

            var parts: [String] = []
            if let deviceName { parts.append(deviceName) }
            else if let productType { parts.append(productType) }
            if let lastBackupDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                parts.append(formatter.string(from: lastBackupDate))
            }
            if !parts.isEmpty {
                label = "iOS backup: \(parts.joined(separator: " — "))"
            }
        }

        iosBackupCache.set(backupRootPath, label)
        return label
    }
}
