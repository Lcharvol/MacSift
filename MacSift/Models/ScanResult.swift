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

    init(filesByCategory: [FileCategory: [ScannedFile]], scanDuration: TimeInterval) {
        self.filesByCategory = filesByCategory
        self.scanDuration = scanDuration

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
}
