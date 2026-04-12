import Foundation

struct ScanProgress: Sendable {
    let filesFound: Int
    let currentSize: Int64
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

        var allFiles: [FileCategory: [ScannedFile]] = [:]

        await withTaskGroup(of: [ScannedFile].self) { group in
            for (url, hintCategory) in scanTargets {
                group.addTask {
                    Self.scanDirectory(
                        url,
                        hintCategory: hintCategory,
                        classifier: classifier,
                        excludedPaths: excludedPaths,
                        maxDepth: maxDepth
                    )
                }
            }

            group.addTask {
                Self.scanForLargeFiles(
                    in: homeDirectory,
                    classifier: classifier,
                    excludedPaths: excludedPaths
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
        maxDepth: Int
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
        }

        return files
    }

    private static func scanForLargeFiles(
        in directory: URL,
        classifier: CategoryClassifier,
        excludedPaths: [String]
    ) -> [ScannedFile] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let skipPrefixes = ["Library/Caches", "Library/Logs", "Library/Application Support"]
        let homePath = directory.path(percentEncoded: false)
        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        var files: [ScannedFile] = []

        while let next = enumerator.nextObject() {
            guard let fileURL = next as? URL else { continue }

            let filePath = fileURL.path(percentEncoded: false)
            let relativePath = filePath.hasPrefix(homePrefix) ? String(filePath.dropFirst(homePrefix.count)) : filePath

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
        }

        return files
    }
}
