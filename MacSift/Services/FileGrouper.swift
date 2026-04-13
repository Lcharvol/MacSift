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
            representativeURL: file.url
        )
    }
}
