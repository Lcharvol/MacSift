import Testing
import Foundation
@testable import MacSift

/// Fills FileGrouper coverage for the categories the original test suite
/// didn't touch: devCaches, mailDownloads, oldDownloads, appData. The
/// existing suite covers cache, iosBackups, tempFiles, largeFiles, logs,
/// xcodeJunk — we add the rest so the grouping strategies can't regress
/// silently.
@Suite("FileGrouper · additional category coverage")
struct FileGrouperCoverageTests {
    /// FileGrouper matches against `CategoryClassifier.sharedHomePrefix`
    /// (the real user home), so test fixtures must be rooted there too.
    /// We don't actually create files on disk — only build `ScannedFile`
    /// values whose path strings look correct to the grouper.
    private var homePrefix: String { CategoryClassifier.sharedHomePrefix }

    private func makeFile(_ relative: String, size: Int64, category: FileCategory) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "\(homePrefix)\(relative)"),
            size: size,
            category: category,
            description: "",
            modificationDate: .now,
            isDirectory: false
        )
    }

    @Test func devCachesGroupByPackageManager() {
        let files = [
            makeFile(".npm/_cacache/a", size: 100, category: .devCaches),
            makeFile(".npm/_cacache/b", size: 200, category: .devCaches),
            makeFile(".yarn/cache/foo", size: 300, category: .devCaches),
            makeFile(".pnpm-store/v3/bar", size: 400, category: .devCaches),
        ]
        let groups = FileGrouper.group(files)

        // Each package manager gets its own bucket.
        let labels = Set(groups.map(\.label))
        #expect(labels.count >= 3, "Expected separate groups per manager, got \(labels)")

        // Total size is preserved across all groups.
        let total = groups.reduce(0) { $0 + $1.totalSize }
        #expect(total == 1000)
    }

    @Test func mailDownloadsCollapseIntoOneGroup() {
        let files = [
            makeFile("Library/Mail Downloads/a.pdf", size: 1_000_000, category: .mailDownloads),
            makeFile("Library/Mail Downloads/b.docx", size: 2_000_000, category: .mailDownloads),
            makeFile("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/c.zip",
                    size: 3_000_000, category: .mailDownloads),
        ]
        let groups = FileGrouper.group(files)

        // The grouper collapses mail attachments into a single row.
        #expect(groups.count == 1)
        #expect(groups.first?.fileCount == 3)
        #expect(groups.first?.totalSize == 6_000_000)
    }

    @Test func oldDownloadsStayAsSingletons() {
        let files = [
            makeFile("Downloads/big-archive.zip", size: 500_000_000, category: .oldDownloads),
            makeFile("Downloads/vintage-photo.jpg", size: 1_000_000, category: .oldDownloads),
        ]
        let groups = FileGrouper.group(files)

        // Each downloaded file is its own row so the user can decide
        // per-file without a roll-up.
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.fileCount == 1 })
    }

    @Test func orphanedAppDataGroupsByFolderName() {
        let files = [
            makeFile("Library/Application Support/OldApp/data.db", size: 100, category: .appData),
            makeFile("Library/Application Support/OldApp/settings.plist", size: 50, category: .appData),
            makeFile("Library/Application Support/AnotherOldApp/stuff", size: 200, category: .appData),
        ]
        let groups = FileGrouper.group(files)

        // Two folders → two groups.
        #expect(groups.count == 2)
        // OldApp should contain both files.
        let oldApp = groups.first { $0.label.contains("OldApp") || $0.fileCount == 2 }
        #expect(oldApp?.fileCount == 2)
    }

    @Test func emptyFilesForAnyCategoryReturnsEmpty() {
        #expect(FileGrouper.group([]).isEmpty)
    }

    @Test func topFilesAreLimitedEvenForHugeGroups() {
        // Build 50 files in the same cache bundle — topFiles should cap at 5.
        let files = (0..<50).map { i in
            makeFile("Library/Caches/com.test.app/file\(i)", size: Int64((i + 1) * 100), category: .cache)
        }
        let groups = FileGrouper.group(files)
        #expect(groups.count == 1)
        let group = groups[0]
        #expect(group.fileCount == 50)
        #expect(group.topFiles.count <= 5)
        // And topFiles are the LARGEST ones (descending size).
        let sizes = group.topFiles.map(\.size)
        #expect(sizes == sizes.sorted(by: >))
    }
}
