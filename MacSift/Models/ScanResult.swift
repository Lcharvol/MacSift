import Foundation

struct ScanResult: Sendable {
    let filesByCategory: [FileCategory: [ScannedFile]]
    let scanDuration: TimeInterval

    var totalSize: Int64 {
        filesByCategory.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    var sizeByCategory: [FileCategory: Int64] {
        filesByCategory.mapValues { files in
            files.reduce(0) { $0 + $1.size }
        }
    }

    var totalFileCount: Int {
        filesByCategory.values.reduce(0) { $0 + $1.count }
    }

    static let empty = ScanResult(filesByCategory: [:], scanDuration: 0)
}
