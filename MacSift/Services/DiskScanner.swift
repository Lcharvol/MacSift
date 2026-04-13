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

actor DiskScanner {
    private let classifier: CategoryClassifier
    private let exclusionManager: ExclusionManager
    private let homeDirectory: URL
    private let maxDepth: Int

    private var progressContinuation: AsyncStream<ScanProgress>.Continuation?
    private var _progressStream: AsyncStream<ScanProgress>?

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

    func progressStream() -> AsyncStream<ScanProgress> {
        if let existing = _progressStream {
            return existing
        }
        let stream = AsyncStream<ScanProgress> { continuation in
            self.progressContinuation = continuation
        }
        _progressStream = stream
        return stream
    }

    func scan() async -> ScanResult {
        let startTime = Date()

        // Snapshot exclusions once at the start (avoids hot-loop hops to MainActor)
        let excludedPaths: [String] = await MainActor.run {
            exclusionManager.excludedPaths.map { $0.path(percentEncoded: false) }
        }

        let scanTargets: [(URL, FileCategory?)] = [
            (homeDirectory.appending(path: "Library/Caches"), .cache),
            (homeDirectory.appending(path: "Library/Logs"), .logs),
            (homeDirectory.appending(path: "Library/Application Support"), nil),
            (URL(filePath: "/private/var/log"), .logs),
            (URL(filePath: "/tmp"), .tempFiles),
        ]

        let classifier = self.classifier
        let maxDepth = self.maxDepth
        let homeDirectory = self.homeDirectory
        let continuation = self.progressContinuation

        var allFiles: [FileCategory: [ScannedFile]] = [:]

        await withTaskGroup(of: [ScannedFile].self) { group in
            for (url, hintCategory) in scanTargets {
                group.addTask {
                    Self.scanDirectory(
                        url,
                        hintCategory: hintCategory,
                        classifier: classifier,
                        excludedPaths: excludedPaths,
                        maxDepth: maxDepth,
                        progress: continuation
                    )
                }
            }

            group.addTask {
                Self.scanForLargeFiles(
                    in: homeDirectory,
                    classifier: classifier,
                    excludedPaths: excludedPaths,
                    progress: continuation
                )
            }

            for await files in group {
                for file in files {
                    allFiles[file.category, default: []].append(file)
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        progressContinuation?.finish()

        return ScanResult(filesByCategory: allFiles, scanDuration: duration)
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
    ) -> [ScannedFile] {
        let fm = FileManager.default

        if isExcluded(directory, excludedPaths: excludedPaths) { return [] }
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        guard fm.isReadableFile(atPath: directory.path(percentEncoded: false)) else { return [] }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return [] }

        var files: [ScannedFile] = []
        var deltaFiles = 0
        var deltaSize: Int64 = 0

        while let next = enumerator.nextObject() {
            guard let fileURL = next as? URL else { continue }

            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if isExcluded(fileURL, excludedPaths: excludedPaths) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

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
            } else if let classified = classifier.classify(url: fileURL, size: size) {
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

        return files
    }

    private static func scanForLargeFiles(
        in directory: URL,
        classifier: CategoryClassifier,
        excludedPaths: [String],
        progress: AsyncStream<ScanProgress>.Continuation?
    ) -> [ScannedFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        // Skip the entire Library (already scanned by other tasks), version control,
        // node_modules, build outputs, and Trash — these can have millions of small files
        // and dramatically slow down the large-file scan.
        let skipPrefixes = [
            "Library/",
            ".Trash",
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
        ]
        let skipNames: Set<String> = [
            "node_modules", ".git", ".cache", "Pods", "DerivedData",
            ".build", ".next", ".nuxt", "venv", ".venv", "__pycache__",
            ".Trash", ".npm", ".pnpm-store", ".yarn",
        ]
        let homePath = directory.path(percentEncoded: false)
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        var files: [ScannedFile] = []
        var deltaFiles = 0
        var deltaSize: Int64 = 0
        var visited = 0

        while let next = enumerator.nextObject() {
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

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

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

        return files
    }
}
