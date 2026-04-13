import Testing
import Foundation
@testable import MacSift

@Suite("FileGrouper")
struct FileGrouperTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private func makeFile(_ relative: String, size: Int64, category: FileCategory) -> ScannedFile {
        let url = home.appending(path: relative)
        return ScannedFile(
            url: url,
            size: size,
            category: category,
            description: "test",
            modificationDate: .now,
            isDirectory: false
        )
    }

    @Test func emptyInputProducesEmptyOutput() {
        let groups = FileGrouper.group([])
        #expect(groups.isEmpty)
    }

    @Test func cacheFilesAreGroupedByBundleId() {
        let files: [ScannedFile] = [
            makeFile("Library/Caches/com.apple.Safari/data1.db", size: 100, category: .cache),
            makeFile("Library/Caches/com.apple.Safari/data2.db", size: 200, category: .cache),
            makeFile("Library/Caches/com.google.Chrome/cookies", size: 50, category: .cache),
        ]
        let groups = FileGrouper.group(files)

        #expect(groups.count == 2)
        // Sorted by size descending — Safari (300) then Chrome (50)
        #expect(groups[0].label == "Safari")
        #expect(groups[0].fileCount == 2)
        #expect(groups[0].totalSize == 300)
        #expect(groups[1].label == "Google Chrome")
        #expect(groups[1].totalSize == 50)
    }

    @Test func iosBackupsAreGroupedByBackupRoot() {
        let backup1 = "Library/Application Support/MobileSync/Backup/AAAA-1111"
        let backup2 = "Library/Application Support/MobileSync/Backup/BBBB-2222"
        let files: [ScannedFile] = [
            makeFile("\(backup1)/Manifest.db", size: 1000, category: .iosBackups),
            makeFile("\(backup1)/Info.plist", size: 500, category: .iosBackups),
            makeFile("\(backup2)/Manifest.db", size: 200, category: .iosBackups),
        ]
        let groups = FileGrouper.group(files)

        #expect(groups.count == 2)
        #expect(groups[0].fileCount == 2)
        #expect(groups[0].totalSize == 1500)
        #expect(groups[1].totalSize == 200)
    }

    @Test func tempFilesStayAsSingletons() {
        let files: [ScannedFile] = [
            makeFile("../../tmp/a.tmp", size: 10, category: .tempFiles),
            makeFile("../../tmp/b.tmp", size: 20, category: .tempFiles),
        ]
        let groups = FileGrouper.group(files)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.fileCount == 1 })
    }

    @Test func largeFilesStayAsSingletons() {
        let files: [ScannedFile] = [
            makeFile("Documents/big.mov", size: 1_000_000_000, category: .largeFiles),
        ]
        let groups = FileGrouper.group(files)
        #expect(groups.count == 1)
        #expect(groups[0].fileCount == 1)
        #expect(groups[0].label == "big.mov")
    }

    @Test func topFilesAreCachedPerGroup() {
        let files: [ScannedFile] = (1...10).map { i in
            makeFile("Library/Caches/com.test.app/file\(i)", size: Int64(i * 100), category: .cache)
        }
        let groups = FileGrouper.group(files)
        #expect(groups.count == 1)
        #expect(groups[0].topFiles.count == 5)
        // Should be sorted by size descending
        #expect(groups[0].topFiles[0].size == 1000)
        #expect(groups[0].topFiles[4].size == 600)
    }

    // MARK: - Xcode junk grouping

    @Test func groupsDerivedDataByProjectNameStrippingHash() {
        let derivedData = home.appending(path: "Library/Developer/Xcode/DerivedData")
        let files: [ScannedFile] = [
            ScannedFile(
                url: derivedData.appending(path: "MacSift-abcdef1234/Build/Intermediates/a.o"),
                size: 1000,
                category: .xcodeJunk,
                description: "",
                modificationDate: .now,
                isDirectory: false
            ),
            ScannedFile(
                url: derivedData.appending(path: "MacSift-abcdef1234/Build/Intermediates/b.o"),
                size: 2000,
                category: .xcodeJunk,
                description: "",
                modificationDate: .now,
                isDirectory: false
            ),
            ScannedFile(
                url: derivedData.appending(path: "OtherApp-xyz987/Build/Intermediates/c.o"),
                size: 500,
                category: .xcodeJunk,
                description: "",
                modificationDate: .now,
                isDirectory: false
            ),
        ]
        let groups = FileGrouper.group(files)
        #expect(groups.count == 2)

        let macsiftGroup = groups.first { $0.label.contains("MacSift") }
        #expect(macsiftGroup != nil)
        #expect(macsiftGroup?.label == "DerivedData · MacSift")
        #expect(macsiftGroup?.fileCount == 2)

        let otherGroup = groups.first { $0.label.contains("OtherApp") }
        #expect(otherGroup?.label == "DerivedData · OtherApp")
    }

    @Test func groupsArchivesIntoOneBucket() {
        let archives = home.appending(path: "Library/Developer/Xcode/Archives")
        let files: [ScannedFile] = [
            ScannedFile(
                url: archives.appending(path: "2024-01-01/A.xcarchive/Info.plist"),
                size: 1000, category: .xcodeJunk, description: "",
                modificationDate: .now, isDirectory: false
            ),
            ScannedFile(
                url: archives.appending(path: "2024-02-01/B.xcarchive/Info.plist"),
                size: 2000, category: .xcodeJunk, description: "",
                modificationDate: .now, isDirectory: false
            ),
        ]
        let groups = FileGrouper.group(files)
        #expect(groups.count == 1)
        #expect(groups[0].label == "Xcode archives")
        #expect(groups[0].fileCount == 2)
    }

    @Test func groupsDeviceSupportByVersion() {
        let root = home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport")
        let files: [ScannedFile] = [
            ScannedFile(
                url: root.appending(path: "17.4 (21E219)/Symbols/lib.dylib"),
                size: 1000, category: .xcodeJunk, description: "",
                modificationDate: .now, isDirectory: false
            ),
            ScannedFile(
                url: root.appending(path: "18.0 (22A123)/Symbols/lib.dylib"),
                size: 2000, category: .xcodeJunk, description: "",
                modificationDate: .now, isDirectory: false
            ),
        ]
        let groups = FileGrouper.group(files)
        #expect(groups.count == 2)
        #expect(groups.contains { $0.label.contains("17.4") })
        #expect(groups.contains { $0.label.contains("18.0") })
    }

    @Test func systemLogsBucketCatchesPrivateVarLog() {
        let url = URL(filePath: "/private/var/log/system.log")
        let file = ScannedFile(
            url: url,
            size: 100,
            category: .logs,
            description: "system",
            modificationDate: .now,
            isDirectory: false
        )
        let groups = FileGrouper.group([file])
        #expect(groups.count == 1)
        #expect(groups[0].label == "System logs")
    }
}
