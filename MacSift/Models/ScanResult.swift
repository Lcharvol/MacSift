import Foundation

/// Result of a completed scan. The aggregate metrics (`sizeByCategory`,
/// `totalSize`, `totalFileCount`) are pre-computed at construction time —
/// **never** iterate `filesByCategory` from a SwiftUI view body.
struct ScanResult: Sendable {
    let filesByCategory: [FileCategory: [ScannedFile]]
    let scanDuration: TimeInterval
    let sizeByCategory: [FileCategory: Int64]
    let totalSize: Int64
    let totalFileCount: Int
    let countByCategory: [FileCategory: Int]
    /// Count of files / directories the scanner couldn't read due to
    /// permissions or I/O errors. Reported to the user so a partial scan
    /// is never silently presented as complete.
    let inaccessibleCount: Int
    /// Sample of paths the scanner couldn't read. Capped at 50 to keep the
    /// result small — the full count is in `inaccessibleCount`. Used by the
    /// inspector so the user can see *which* folders to grant access to,
    /// rather than just "12 inaccessible".
    let inaccessiblePaths: [String]

    init(
        filesByCategory: [FileCategory: [ScannedFile]],
        scanDuration: TimeInterval,
        inaccessibleCount: Int = 0,
        inaccessiblePaths: [String] = []
    ) {
        self.filesByCategory = filesByCategory
        self.scanDuration = scanDuration
        self.inaccessibleCount = inaccessibleCount
        self.inaccessiblePaths = inaccessiblePaths

        // Compute aggregates once, here. These were previously computed
        // properties that iterated all files on every access — which meant
        // MainView's body was scanning 50k+ files 5-6 times per render,
        // causing a visible freeze on category switch.
        var sizes: [FileCategory: Int64] = [:]
        var counts: [FileCategory: Int] = [:]
        var total: Int64 = 0
        var totalCount = 0
        for (category, files) in filesByCategory {
            var categorySize: Int64 = 0
            for file in files {
                categorySize += file.size
            }
            sizes[category] = categorySize
            counts[category] = files.count
            total += categorySize
            totalCount += files.count
        }
        self.sizeByCategory = sizes
        self.countByCategory = counts
        self.totalSize = total
        self.totalFileCount = totalCount
    }

    static let empty = ScanResult(filesByCategory: [:], scanDuration: 0)

    /// Return a filtered copy that only contains files whose `volumeID`
    /// matches. Nil means "all volumes" and returns `self` unchanged.
    /// Recomputes aggregates — do NOT call on every render. Cache it at
    /// the ViewModel layer.
    func filteringVolume(_ volumeID: String?) -> ScanResult {
        guard let volumeID else { return self }
        let filtered = filesByCategory.mapValues { files in
            files.filter { $0.volumeID == volumeID }
        }.filter { !$0.value.isEmpty }
        return ScanResult(
            filesByCategory: filtered,
            scanDuration: scanDuration,
            inaccessibleCount: inaccessibleCount,
            inaccessiblePaths: inaccessiblePaths
        )
    }
}
