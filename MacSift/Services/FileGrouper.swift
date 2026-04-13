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
    /// How many largest files to keep around for the inspector preview.
    static let topFilesPreviewCount = 5

    /// Returns the top-N largest files without paying for a full sort.
    /// O(n log k) where k is the desired count.
    private static func topNLargest(_ files: [ScannedFile], count: Int) -> [ScannedFile] {
        guard files.count > count else {
            return files.sorted { $0.size > $1.size }
        }
        // Partial sort: keep a min-heap of size N; replace the smallest as we go.
        var heap = Array(files.prefix(count))
        heap.sort { $0.size < $1.size }
        for file in files.dropFirst(count) {
            if file.size > heap[0].size {
                heap[0] = file
                // Re-sort the small heap (count is tiny, so this is fine)
                heap.sort { $0.size < $1.size }
            }
        }
        return heap.reversed()
    }

    /// Pre-compute the most recent modification date across all files so
    /// the "Most Recent" sort doesn't walk every file on every render.
    private static func mostRecentDate(in files: [ScannedFile]) -> Date {
        var result = Date.distantPast
        for file in files where file.modificationDate > result {
            result = file.modificationDate
        }
        return result
    }

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
        case .xcodeJunk:
            return groupByXcodeJunk(files: files)
        case .devCaches:
            return groupByDevCache(files: files)
        case .mailDownloads:
            // All mail attachments collapse into a single row — the individual
            // file names are noisy and the user just wants "clear mail downloads".
            let total = files.reduce(0 as Int64) { $0 + $1.size }
            let representative = files[0].url.deletingLastPathComponent()
            return [FileGroup(
                id: "mailDownloads:all",
                label: "Mail attachments",
                category: .mailDownloads,
                totalSize: total,
                fileCount: files.count,
                files: files,
                topFiles: topNLargest(files, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: files),
                representativeURL: representative
            )]
        case .timeMachineSnapshots, .tempFiles, .largeFiles, .oldDownloads:
            return files.map(singletonGroup)
        }
    }

    // MARK: - Xcode Junk grouping

    /// Groups Xcode junk by the owning project name for DerivedData, or by
    /// subpath (Archives, iOS DeviceSupport, CoreSimulator Caches) for the rest.
    private static func groupByXcodeJunk(files: [ScannedFile]) -> [FileGroup] {
        let homePrefix = CategoryClassifier.sharedHomePrefix
        let derivedDataRoot = "\(homePrefix)Library/Developer/Xcode/DerivedData/"
        let archivesRoot = "\(homePrefix)Library/Developer/Xcode/Archives/"
        let deviceSupportRoot = "\(homePrefix)Library/Developer/Xcode/iOS DeviceSupport/"
        let simulatorCachesRoot = "\(homePrefix)Library/Developer/CoreSimulator/Caches/"

        var buckets: [String: [ScannedFile]] = [:]
        var bucketLabels: [String: String] = [:]

        for file in files {
            let path = file.path
            let key: String
            let label: String

            if path.hasPrefix(derivedDataRoot) {
                // Xcode project folders are named "ProjectName-<hash>"
                let relative = String(path.dropFirst(derivedDataRoot.count))
                let folder = relative.split(separator: "/").first.map(String.init) ?? "DerivedData"
                // Strip the "-xxxxxxxx" hash suffix to show a clean project name
                let projectName: String = {
                    if let dashIdx = folder.lastIndex(of: "-") {
                        return String(folder[folder.startIndex..<dashIdx])
                    }
                    return folder
                }()
                key = "derivedData:\(folder)"
                label = "DerivedData · \(projectName)"
            } else if path.hasPrefix(archivesRoot) {
                key = "xcodeJunk:archives"
                label = "Xcode archives"
            } else if path.hasPrefix(deviceSupportRoot) {
                // Group by iOS version folder e.g. "17.4 (21E219)"
                let relative = String(path.dropFirst(deviceSupportRoot.count))
                let folder = relative.split(separator: "/").first.map(String.init) ?? "DeviceSupport"
                key = "deviceSupport:\(folder)"
                label = "iOS \(folder) debug symbols"
            } else if path.hasPrefix(simulatorCachesRoot) {
                key = "xcodeJunk:simulatorCaches"
                label = "CoreSimulator caches"
            } else {
                key = "xcodeJunk:other"
                label = "Xcode other"
            }

            buckets[key, default: []].append(file)
            bucketLabels[key] = label
        }

        return buckets.map { key, bucketFiles in
            let total = bucketFiles.reduce(0 as Int64) { $0 + $1.size }
            return FileGroup(
                id: "xcode:\(key)",
                label: bucketLabels[key] ?? key,
                category: .xcodeJunk,
                totalSize: total,
                fileCount: bucketFiles.count,
                files: bucketFiles,
                topFiles: topNLargest(bucketFiles, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: bucketFiles),
                representativeURL: bucketFiles[0].url.deletingLastPathComponent()
            )
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Dev cache grouping

    /// Groups developer caches by the root cache folder (`.npm`, `.yarn`,
    /// `Homebrew`, etc.) so the user sees one row per package manager.
    private static func groupByDevCache(files: [ScannedFile]) -> [FileGroup] {
        let homePrefix = CategoryClassifier.sharedHomePrefix

        // Ordered list — longer prefixes must come first so `.cache/pip`
        // matches before `.cache`.
        let rootPatterns: [(prefix: String, label: String, key: String)] = [
            (".cache/huggingface", "Hugging Face", "huggingface"),
            (".cache/pip", "pip", "pip"),
            (".cache/yarn", "yarn cache", "yarn-cache"),
            (".cache", "Shell caches", "cache"),
            (".npm", "npm", "npm"),
            (".yarn", "yarn", "yarn"),
            (".pnpm-store", "pnpm", "pnpm"),
            (".cargo/registry/cache", "Cargo registry", "cargo"),
            (".rustup/toolchains", "Rust toolchains", "rustup"),
            ("go/pkg/mod", "Go modules", "go"),
            ("Library/Caches/Homebrew", "Homebrew", "homebrew"),
            ("Library/Caches/pip", "pip (Library)", "pip-lib"),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode cache", "xcode-cache"),
        ]

        var buckets: [String: (label: String, files: [ScannedFile])] = [:]
        for file in files {
            let path = file.path
            for root in rootPatterns {
                if path.hasPrefix("\(homePrefix)\(root.prefix)") {
                    buckets[root.key, default: (root.label, [])].files.append(file)
                    if buckets[root.key]?.label == nil {
                        buckets[root.key]?.label = root.label
                    }
                    break
                }
            }
        }

        return buckets.map { key, bucket in
            let total = bucket.files.reduce(0 as Int64) { $0 + $1.size }
            return FileGroup(
                id: "devCache:\(key)",
                label: bucket.label,
                category: .devCaches,
                totalSize: total,
                fileCount: bucket.files.count,
                files: bucket.files,
                topFiles: topNLargest(bucket.files, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: bucket.files),
                representativeURL: bucket.files[0].url.deletingLastPathComponent()
            )
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Library-prefix grouping

    /// Groups files by the first path component after `Library/<Caches|Logs|Application Support>/`.
    /// Files that don't match (e.g., `/private/var/log` system logs) are grouped
    /// into a single "System logs" bucket.
    private static func groupByLibrarySubpath(files: [ScannedFile], category: FileCategory) -> [FileGroup] {
        let libraryRoots: [String] = {
            let homePrefix = CategoryClassifier.sharedHomePrefix
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
            let label = BundleNames.humanLabel(for: key)
            // Representative URL = the parent folder (the first matching root + key)
            let representative = bucketFiles[0].url.deletingLastPathComponent()
            groups.append(FileGroup(
                id: "\(category.rawValue):\(key)",
                label: label,
                category: category,
                totalSize: total,
                fileCount: bucketFiles.count,
                files: bucketFiles,
                topFiles: topNLargest(bucketFiles, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: bucketFiles),
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
                topFiles: topNLargest(systemBucket, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: systemBucket),
                representativeURL: systemBucket[0].url
            ))
        }

        return groups.sorted { $0.totalSize > $1.totalSize }
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
                topFiles: topNLargest(bucketFiles, count: topFilesPreviewCount),
                mostRecentModificationDate: mostRecentDate(in: bucketFiles),
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
            topFiles: [file],
            mostRecentModificationDate: file.modificationDate,
            representativeURL: file.url
        )
    }
}
