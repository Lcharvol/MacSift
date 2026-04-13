import Foundation

/// Builds aggregated `FileGroup`s from a flat list of `ScannedFile`s.
///
/// Grouping rules per category:
/// - `.cache` / `.logs` / `.appData`: group by the first path component after
///   the well-known root (e.g., everything under `Library/Caches/com.apple.Safari`
///   becomes one "Safari" group).
/// - `.iosBackups`: group by the backup root folder (the UUID directory under
///   `MobileSync/Backup/`). Each device backup is one row.
/// - `.timeMachineSnapshots`: each snapshot is already a single synthetic file
///   so it stays as a singleton group.
/// - `.tempFiles` / `.largeFiles`: kept as singleton groups (one per file).
enum FileGrouper {
    static func group(_ files: [ScannedFile]) -> [FileGroup] {
        guard !files.isEmpty else { return [] }
        // All files in this batch should belong to the same category — but we
        // don't enforce that, we just dispatch by category per file.
        let firstCategory = files[0].category
        switch firstCategory {
        case .cache, .logs, .appData:
            return groupByLibrarySubpath(files: files, category: firstCategory)
        case .iosBackups:
            return groupByIOSBackup(files: files)
        case .timeMachineSnapshots, .tempFiles, .largeFiles:
            return files.map(singletonGroup)
        }
    }

    // MARK: - Library-prefix grouping

    /// Groups files by the first path component after `Library/<Caches|Logs|Application Support>/`.
    /// Files that don't match (e.g., `/private/var/log` system logs) are grouped
    /// into a single "System logs" bucket.
    private static func groupByLibrarySubpath(files: [ScannedFile], category: FileCategory) -> [FileGroup] {
        let libraryRoots: [String] = {
            let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            let homePrefix = home.hasSuffix("/") ? home : home + "/"
            switch category {
            case .cache: return ["\(homePrefix)Library/Caches/"]
            case .logs: return ["\(homePrefix)Library/Logs/"]
            case .appData: return ["\(homePrefix)Library/Application Support/"]
            default: return []
            }
        }()

        // Buckets keyed by group key (the bundle/app folder name)
        var buckets: [String: [ScannedFile]] = [:]
        var systemBucket: [ScannedFile] = []

        for file in files {
            let path = file.path
            var matchedKey: String? = nil
            for root in libraryRoots {
                if path.hasPrefix(root) {
                    let relative = String(path.dropFirst(root.count))
                    let firstComponent = relative.split(separator: "/").first.map(String.init) ?? relative
                    matchedKey = firstComponent
                    break
                }
            }

            if let key = matchedKey {
                buckets[key, default: []].append(file)
            } else {
                systemBucket.append(file)
            }
        }

        var groups: [FileGroup] = []

        for (key, bucketFiles) in buckets {
            let total = bucketFiles.reduce(0 as Int64) { $0 + $1.size }
            let label = humanLabelForBundleKey(key)
            // Representative URL = the parent folder (the first matching root + key)
            let representative = bucketFiles[0].url.deletingLastPathComponent()
            groups.append(FileGroup(
                id: "\(category.rawValue):\(key)",
                label: label,
                category: category,
                totalSize: total,
                fileCount: bucketFiles.count,
                files: bucketFiles,
                representativeURL: representative
            ))
        }

        if !systemBucket.isEmpty {
            let total = systemBucket.reduce(0 as Int64) { $0 + $1.size }
            groups.append(FileGroup(
                id: "\(category.rawValue):__system__",
                label: category == .logs ? "System logs" : "System data",
                category: category,
                totalSize: total,
                fileCount: systemBucket.count,
                files: systemBucket,
                representativeURL: systemBucket[0].url
            ))
        }

        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    /// Translates reverse-DNS bundle ids and folder names into human labels.
    private static func humanLabelForBundleKey(_ key: String) -> String {
        let lowered = key.lowercased()
        let knownApps: [(pattern: String, label: String)] = [
            ("com.apple.safari", "Safari"),
            ("com.apple.mail", "Mail"),
            ("com.apple.dt.xcode", "Xcode"),
            ("com.apple.dt", "Xcode"),
            ("com.apple.finder", "Finder"),
            ("com.apple.spotlight", "Spotlight"),
            ("com.apple.messages", "Messages"),
            ("com.apple.notes", "Notes"),
            ("com.google.chrome", "Google Chrome"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.spotify.client", "Spotify"),
            ("com.tinyspeck.slackmacgap", "Slack"),
            ("com.hnc.discord", "Discord"),
            ("com.figma.desktop", "Figma"),
            ("com.microsoft.vscode", "Visual Studio Code"),
            ("com.docker.docker", "Docker"),
        ]
        for app in knownApps {
            if lowered == app.pattern || lowered.hasPrefix(app.pattern + ".") {
                return app.label
            }
        }
        // Generic reverse-DNS handling: take the last meaningful segment
        if lowered.contains(".") {
            let segments = key.split(separator: ".").map(String.init)
            if let last = segments.last, last != "app" {
                return last.capitalized
            }
            if segments.count >= 2 {
                return segments[segments.count - 2].capitalized
            }
        }
        return key
    }

    // MARK: - iOS Backups grouping

    private static func groupByIOSBackup(files: [ScannedFile]) -> [FileGroup] {
        var buckets: [String: [ScannedFile]] = [:]
        for file in files {
            let path = file.path
            guard let range = path.range(of: "MobileSync/Backup/") else { continue }
            let afterBackup = path[range.upperBound...]
            let backupID: String
            if let slash = afterBackup.firstIndex(of: "/") {
                backupID = String(afterBackup[..<slash])
            } else {
                backupID = String(afterBackup)
            }
            buckets[backupID, default: []].append(file)
        }

        return buckets.map { id, bucketFiles in
            let total = bucketFiles.reduce(0 as Int64) { $0 + $1.size }
            // Use the first file's description (which already includes device + date)
            let label = bucketFiles[0].description.replacingOccurrences(of: "iOS backup: ", with: "")
            let backupRoot: URL = {
                let path = bucketFiles[0].path
                if let range = path.range(of: "MobileSync/Backup/\(id)") {
                    return URL(filePath: String(path[..<range.upperBound]))
                }
                return bucketFiles[0].url.deletingLastPathComponent()
            }()
            return FileGroup(
                id: "iosBackup:\(id)",
                label: "iOS backup — \(label)",
                category: .iosBackups,
                totalSize: total,
                fileCount: bucketFiles.count,
                files: bucketFiles,
                representativeURL: backupRoot
            )
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Singleton

    private static func singletonGroup(for file: ScannedFile) -> FileGroup {
        FileGroup(
            id: "single:\(file.id)",
            label: file.name,
            category: file.category,
            totalSize: file.size,
            fileCount: 1,
            files: [file],
            representativeURL: file.url
        )
    }
}
