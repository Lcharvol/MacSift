import Testing
import Foundation
@testable import MacSift

@Suite("ScanResult")
struct ScanResultTests {
    @Test func computesTotalSize() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 200, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/c"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.5)
        #expect(result.totalSize == 600)
    }

    @Test func computesSizeByCategory() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.0)
        #expect(result.sizeByCategory[.cache] == 100)
        #expect(result.sizeByCategory[.logs] == 300)
    }

    @Test func computesTotalFileCount() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 200, category: .logs, description: "", modificationDate: .now, isDirectory: false),
                ScannedFile(url: URL(filePath: "/tmp/c"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.0)
        #expect(result.totalFileCount == 3)
    }

    @Test func emptyResultIsZero() {
        let result = ScanResult.empty
        #expect(result.totalSize == 0)
        #expect(result.totalFileCount == 0)
        #expect(result.sizeByCategory.isEmpty)
    }
}
