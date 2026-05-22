import Foundation

enum FileDescriptions {
    static func describe(url: URL, category: FileCategory, locale: Locale = .current) -> String {
        let name = url.lastPathComponent
        let path = url.path(percentEncoded: false).lowercased()

        switch category {
        case .cache:
            return describeCacheFile(name: name, path: path, locale: locale)
        case .logs:
            return describeLogFile(name: name, path: path, locale: locale)
        case .tempFiles:
            return L10n.format("description.tempFile", defaultValue: "Temporary file: %@", locale: locale, name)
        case .appData:
            return L10n.format("description.appData", defaultValue: "Unused app data: %@", locale: locale, name)
        case .largeFiles:
            return L10n.format("description.largeFile", defaultValue: "Large file: %@", locale: locale, name)
        case .timeMachineSnapshots:
            return L10n.text("description.timeMachineSnapshot", defaultValue: "Time Machine local snapshot", locale: locale)
        case .iosBackups:
            return describeIOSBackup(url: url, locale: locale)
        case .xcodeJunk:
            if path.contains("deriveddata") { return L10n.format("description.xcodeDerivedData", defaultValue: "Xcode derived data: %@", locale: locale, name) }
            if path.contains("archives") { return L10n.format("description.xcodeArchive", defaultValue: "Xcode archive: %@", locale: locale, name) }
            if path.contains("devicesupport") { return L10n.format("description.iosDebugSymbols", defaultValue: "iOS debug symbols: %@", locale: locale, name) }
            if path.contains("coresimulator") { return L10n.format("description.simulatorCache", defaultValue: "Simulator cache: %@", locale: locale, name) }
            return L10n.format("description.xcodeJunk", defaultValue: "Xcode junk: %@", locale: locale, name)
        case .devCaches:
            if path.contains(".npm") { return L10n.format("description.npmCache", defaultValue: "npm cache: %@", locale: locale, name) }
            if path.contains(".yarn") { return L10n.format("description.yarnCache", defaultValue: "yarn cache: %@", locale: locale, name) }
            if path.contains(".pnpm") { return L10n.format("description.pnpmCache", defaultValue: "pnpm cache: %@", locale: locale, name) }
            if path.contains("pip") { return L10n.format("description.pipCache", defaultValue: "pip cache: %@", locale: locale, name) }
            if path.contains("cargo") { return L10n.format("description.cargoCache", defaultValue: "Cargo cache: %@", locale: locale, name) }
            if path.contains("rustup") { return L10n.format("description.rustToolchain", defaultValue: "Rust toolchain: %@", locale: locale, name) }
            if path.contains("go/pkg") { return L10n.format("description.goModule", defaultValue: "Go module: %@", locale: locale, name) }
            if path.contains("homebrew") { return L10n.format("description.homebrewDownload", defaultValue: "Homebrew download: %@", locale: locale, name) }
            return L10n.format("description.devCache", defaultValue: "Dev cache: %@", locale: locale, name)
        case .oldDownloads:
            return L10n.format("description.oldDownload", defaultValue: "Old download: %@", locale: locale, name)
        case .mailDownloads:
            return L10n.format("description.mailAttachment", defaultValue: "Mail attachment: %@", locale: locale, name)
        }
    }

    private static func describeCacheFile(name: String, path: String, locale: Locale) -> String {
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
                return L10n.format("description.namedCache", defaultValue: "%@ cache", locale: locale, app.label)
            }
        }
        return L10n.format("description.applicationCache", defaultValue: "Application cache: %@", locale: locale, name)
    }

    private static func describeLogFile(name: String, path: String, locale: Locale) -> String {
        if path.contains("/private/var/log") {
            return L10n.format("description.systemLog", defaultValue: "System log: %@", locale: locale, name)
        }
        return L10n.format("description.applicationLog", defaultValue: "Application log: %@", locale: locale, name)
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

    private static func describeIOSBackup(url: URL, locale: Locale) -> String {
        let path = url.path(percentEncoded: false)
        // Find the backup root: the path component immediately after "Backup/"
        guard let backupRange = path.range(of: "MobileSync/Backup/") else {
            return L10n.format("description.iosBackupNamed", defaultValue: "iOS backup: %@", locale: locale, url.lastPathComponent)
        }
        let afterBackup = path[backupRange.upperBound...]
        guard let firstSlash = afterBackup.firstIndex(of: "/") ?? afterBackup.endIndex as String.Index? else {
            return L10n.format("description.iosBackupNamed", defaultValue: "iOS backup: %@", locale: locale, url.lastPathComponent)
        }
        let backupID = String(afterBackup[..<firstSlash])
        let backupRootPath = String(path[..<backupRange.upperBound]) + backupID

        let cacheKey = "\(locale.identifier)|\(backupRootPath)"
        if let cached = iosBackupCache.get(cacheKey) {
            return cached
        }

        let infoPlistURL = URL(filePath: backupRootPath).appending(path: "Info.plist")
        var label = L10n.text("description.iosBackup", defaultValue: "iOS backup", locale: locale)
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
                label = L10n.format("description.iosBackupNamed", defaultValue: "iOS backup: %@", locale: locale, parts.joined(separator: " — "))
            }
        }

        iosBackupCache.set(cacheKey, label)
        return label
    }
}
