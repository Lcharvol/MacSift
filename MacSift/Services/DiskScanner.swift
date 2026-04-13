import Foundation

/// A delta event from one of the parallel scan tasks. The consumer (ScanViewModel)
/// accumulates these into the displayed totals so the UI shows real cumulative
/// progress instead of bouncing between each task's local counters.
struct ScanProgress: Sendable {
    let deltaFiles: Int
    let deltaSize: Int64
    let currentPath: String
    let category: FileCategory?
}

/// Result of scanning a single root directory. Bundles the files found with
/// a count of items that couldn't be read (permission errors, broken links,
/// corrupted metadata). These are aggregated across all scan tasks.
struct ScanRootResult: Sendable {
    var files: [ScannedFile]
    var inaccessibleCount: Int
}

struct DiskScanner: Sendable {
    let classifier: CategoryClassifier
    let exclusionManager: ExclusionManager
    let homeDirectory: URL
    let maxDepth: Int

    init(
        classifier: CategoryClassifier,
        exclusionManager: ExclusionManager,
        homeDirectory: URL? = nil,
        maxDepth: Int = 20
    ) {
        self.classifier = classifier
        self.exclusionManager = exclusionManager
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.maxDepth = maxDepth
    }

    /// Run a scan and emit progress to the supplied continuation. Cancellation
    /// is honored via Task cancellation — pass nil for the continuation if you
    /// don't need progress events.
    func scan(progress: AsyncStream<ScanProgress>.Continuation? = nil) async -> ScanResult {
        let startTime = Date()

        // Snapshot exclusions once at the start (avoids hot-loop hops to MainActor)
        let excludedPaths: [String] = await MainActor.run {
            exclusionManager.excludedPaths.map { $0.path(percentEncoded: false) }
        }

        let scanTargets: [(URL, FileCategory?)] = [
            (homeDirectory.appending(path: "Library/Caches"), .cache),
            (homeDirectory.appending(path: "Library/Logs"), .logs),
            // Hint nil so the classifier handles it: iOS backups inside this tree
            // need to be tagged as .iosBackups, the rest falls back to .appData.
            (homeDirectory.appending(path: "Library/Application Support"), nil),
            (URL(filePath: "/private/var/log"), .logs),
            (URL(filePath: "/tmp"), .tempFiles),
            // Xcode junk — hint nil so the classifier picks the right subcategory
            // for files that might match multiple rules (e.g., DerivedData vs. a
            // cache path inside it).
            (homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData"), .xcodeJunk),
            (homeDirectory.appending(path: "Library/Developer/Xcode/Archives"), .xcodeJunk),
            (homeDirectory.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"), .xcodeJunk),
            (homeDirectory.appending(path: "Library/Developer/CoreSimulator/Caches"), .xcodeJunk),
            // Developer caches
            (homeDirectory.appending(path: ".npm"), .devCaches),
            (homeDirectory.appending(path: ".yarn"), .devCaches),
            (homeDirectory.appending(path: ".pnpm-store"), .devCaches),
            (homeDirectory.appending(path: ".cache"), .devCaches),
            (homeDirectory.appending(path: ".cargo/registry/cache"), .devCaches),
            (homeDirectory.appending(path: ".rustup/toolchains"), .devCaches),
            (homeDirectory.appending(path: "go/pkg/mod"), .devCaches),
            (homeDirectory.appending(path: "Library/Caches/Homebrew"), .devCaches),
            // Old Downloads — hint nil so the classifier applies the age filter
            (homeDirectory.appending(path: "Downloads"), nil),
            // Mail attachments
            (homeDirectory.appending(path: "Library/Mail Downloads"), .mailDownloads),
            (homeDirectory.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"), .mailDownloads),
        ]

        let classifier = self.classifier
        let maxDepth = self.maxDepth
        let homeDirectory = self.homeDirectory

        var allFiles: [FileCategory: [ScannedFile]] = [:]
        var totalInaccessible = 0

        await withTaskGroup(of: ScanRootResult.self) { group in
            for (url, hintCategory) in scanTargets {
                group.addTask {
                    Self.scanDirectory(
                        url,
                        hintCategory: hintCategory,
                        classifier: classifier,
                        excludedPaths: excludedPaths,
                        maxDepth: maxDepth,
                        progress: progress
                    )
                }
            }

            group.addTask {
                Self.scanForLargeFiles(
                    in: homeDirectory,
                    classifier: classifier,
                    excludedPaths: excludedPaths,
                    progress: progress
                )
            }

            for await root in group {
                totalInaccessible += root.inaccessibleCount
                for file in root.files {
                    allFiles[file.category, default: []].append(file)
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        progress?.finish()

        return ScanResult(
            filesByCategory: allFiles,
            scanDuration: duration,
            inaccessibleCount: totalInaccessible
        )
    }

    private static func isExcluded(_ url: URL, excludedPaths: [String]) -> Bool {
        let path = url.path(percentEncoded: false)
        return excludedPaths.contains { excluded in
            path == excluded || path.hasPrefix(excluded + "/")
        }
    }

    private static func scanDirectory(
        _ directory: URL,
        hintCategory: FileCategory?,
        classifier: CategoryClassifier,
        excludedPaths: [String],
        maxDepth: Int,
        progress: AsyncStream<ScanProgress>.Continuation?
    ) -> ScanRootResult {
        let fm = FileManager.default

        if isExcluded(directory, excludedPaths: excludedPaths) {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }
        guard fm.isReadableFile(atPath: directory.path(percentEncoded: false)) else {
            // Root itself is unreadable — count it as one inaccessible item
            return ScanRootResult(files: [], inaccessibleCount: 1)
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return ScanRootResult(files: [], inaccessibleCount: 1)
        }

        var files: [ScannedFile] = []
        var inaccessible = 0
        var deltaFiles = 0
        var deltaSize: Int64 = 0

        var cancelCheckCounter = 0
        while let next = enumerator.nextObject() {
            // Cooperative cancellation: bail out cleanly if the surrounding
            // Task was cancelled. Check periodically to avoid syscall overhead.
            cancelCheckCounter += 1
            if cancelCheckCounter % 200 == 0 && Task.isCancelled {
                return ScanRootResult(files: files, inaccessibleCount: inaccessible)
            }
            guard let fileURL = next as? URL else { continue }

            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if isExcluded(fileURL, excludedPaths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                inaccessible += 1
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate ?? .distantPast

            let category: FileCategory
            if let hint = hintCategory {
                category = hint
            } else if let classified = classifier.classify(url: fileURL, size: size, modificationDate: modDate) {
                category = classified
            } else {
                continue
            }

            let description = FileDescriptions.describe(url: fileURL, category: category)

            files.append(ScannedFile(
                url: fileURL,
                size: size,
                category: category,
                description: description,
                modificationDate: modDate,
                isDirectory: false
            ))
            deltaFiles += 1
            deltaSize += size

            // Throttle progress: emit a delta every 100 files
            if deltaFiles >= 100 {
                progress?.yield(ScanProgress(
                    deltaFiles: deltaFiles,
                    deltaSize: deltaSize,
                    currentPath: fileURL.lastPathComponent,
                    category: category
                ))
                deltaFiles = 0
                deltaSize = 0
            }
        }

        // Final flush of any remaining delta
        if deltaFiles > 0 {
            progress?.yield(ScanProgress(
                deltaFiles: deltaFiles,
                deltaSize: deltaSize,
                currentPath: directory.lastPathComponent,
                category: hintCategory
            ))
        }

        return ScanRootResult(files: files, inaccessibleCount: inaccessible)
    }

    private static func scanForLargeFiles(
        in directory: URL,
        classifier: CategoryClassifier,
        excludedPaths: [String],
        progress: AsyncStream<ScanProgress>.Continuation?
    ) -> ScanRootResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return ScanRootResult(files: [], inaccessibleCount: 0)
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ScanRootResult(files: [], inaccessibleCount: 1)
        }

        // Skip the entire Library (already scanned by other tasks), version control,
        // node_modules, build outputs, Trash, and Downloads (handled by its own
        // scan target). These can have millions of small files and dramatically
        // slow down the large-file scan — and scanning them here would also
        // double-count files that belong to another explicit scan target.
        let skipPrefixes = [
            "Library/",
            ".Trash",
            "Downloads/",
            "node_modules",
            ".git",
            ".cache",
            ".cargo",
            ".rustup",
            ".npm",
            ".pnpm-store",
            ".yarn",
            "Pods",
            "DerivedData",
            ".build",
            ".next",
            ".nuxt",
            "venv",
            ".venv",
            "__pycache__",
            "go/pkg/mod",
        ]
        let skipNames: Set<String> = [
            "node_modules", ".git", ".cache", "Pods", "DerivedData",
            ".build", ".next", ".nuxt", "venv", ".venv", "__pycache__",
            ".Trash", ".npm", ".pnpm-store", ".yarn",
        ]
        let homePath = directory.path(percentEncoded: false)
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        var files: [ScannedFile] = []
        var inaccessible = 0
        var deltaFiles = 0
        var deltaSize: Int64 = 0
        var visited = 0

        while let next = enumerator.nextObject() {
            if visited % 200 == 0 && Task.isCancelled {
                return ScanRootResult(files: files, inaccessibleCount: inaccessible)
            }
            guard let fileURL = next as? URL else { continue }

            visited += 1
            // Throttle by visited count (we walk many small files between large ones)
            if visited % 500 == 0 {
                progress?.yield(ScanProgress(
                    deltaFiles: deltaFiles,
                    deltaSize: deltaSize,
                    currentPath: fileURL.lastPathComponent,
                    category: .largeFiles
                ))
                deltaFiles = 0
                deltaSize = 0
            }

            let filePath = fileURL.path(percentEncoded: false)
            let relativePath = filePath.hasPrefix(homePrefix) ? String(filePath.dropFirst(homePrefix.count)) : filePath

            // Quick name-based skip (avoids prefix walk for common cases)
            let lastComponent = fileURL.lastPathComponent
            if skipNames.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            if skipPrefixes.contains(where: { relativePath.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }

            if isExcluded(fileURL, excludedPaths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                inaccessible += 1
                continue
            }

            if values.isSymbolicLink == true || values.isDirectory == true { continue }

            let size = Int64(values.fileSize ?? 0)
            guard size > classifier.largeFileThresholdBytes else { continue }

            let modDate = values.contentModificationDate ?? .distantPast
            let description = FileDescriptions.describe(url: fileURL, category: .largeFiles)

            files.append(ScannedFile(
                url: fileURL,
                size: size,
                category: .largeFiles,
                description: description,
                modificationDate: modDate,
                isDirectory: false
            ))
            deltaFiles += 1
            deltaSize += size
        }

        // Final flush
        if deltaFiles > 0 {
            progress?.yield(ScanProgress(
                deltaFiles: deltaFiles,
                deltaSize: deltaSize,
                currentPath: directory.lastPathComponent,
                category: .largeFiles
            ))
        }

        return ScanRootResult(files: files, inaccessibleCount: inaccessible)
    }
}
