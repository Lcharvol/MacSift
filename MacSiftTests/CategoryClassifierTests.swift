import Testing
import Foundation
@testable import MacSift

@Suite("CategoryClassifier")
struct CategoryClassifierTests {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let classifier = CategoryClassifier()

    @Test func classifiesCacheFiles() {
        let url = home.appending(path: "Library/Caches/com.apple.Safari/something.db")
        #expect(classifier.classify(url: url, size: 1000) == .cache)
    }

    @Test func classifiesUserLogs() {
        let url = home.appending(path: "Library/Logs/DiagnosticReports/crash.log")
        #expect(classifier.classify(url: url, size: 1000) == .logs)
    }

    @Test func classifiesSystemLogs() {
        let url = URL(filePath: "/private/var/log/system.log")
        #expect(classifier.classify(url: url, size: 1000) == .logs)
    }

    @Test func classifiesTempFiles() {
        let url = URL(filePath: "/tmp/some_temp_file.dat")
        #expect(classifier.classify(url: url, size: 1000) == .tempFiles)
    }

    @Test func classifiesIOSBackups() {
        let url = home.appending(path: "Library/Application Support/MobileSync/Backup/abc123/Info.plist")
        #expect(classifier.classify(url: url, size: 1000) == .iosBackups)
    }

    @Test func classifiesLargeFiles() {
        let url = home.appending(path: "Documents/huge_video.mov")
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1) == .largeFiles)
    }

    @Test func doesNotClassifySmallFilesAsLarge() {
        let url = home.appending(path: "Documents/small_file.txt")
        #expect(classifier.classify(url: url, size: 1000) == nil)
    }

    @Test func respectsCustomLargeFileThreshold() {
        let customClassifier = CategoryClassifier(largeFileThresholdBytes: 100)
        let url = home.appending(path: "Documents/medium_file.txt")
        #expect(customClassifier.classify(url: url, size: 101) == .largeFiles)
    }

    // MARK: - Orphaned app support

    @Test func orphanedAppSupportIsDetectedAsAppData() {
        // Use a classifier with NO installed apps so everything in
        // Application Support is considered orphaned.
        let classifier = CategoryClassifier(installedAppBundleNames: [])
        let url = home.appending(path: "Library/Application Support/com.vendor.deletedapp/Data.db")
        #expect(classifier.classify(url: url, size: 1000) == .appData)
    }

    @Test func installedAppSupportIsLeftAlone() {
        // Safari is "installed" — its folder should NOT be flagged.
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        let url = home.appending(path: "Library/Application Support/com.apple.Safari/Bookmarks.plist")
        #expect(classifier.classify(url: url, size: 1000) == nil)
    }

    @Test func isOrphanedAppSupportMatchesExactName() {
        let classifier = CategoryClassifier(installedAppBundleNames: ["notion"])
        #expect(classifier.isOrphanedAppSupport(folderName: "Notion") == false)
        #expect(classifier.isOrphanedAppSupport(folderName: "notion") == false)
        #expect(classifier.isOrphanedAppSupport(folderName: "Obsidian") == true)
    }

    @Test func isOrphanedAppSupportMatchesReverseDNS() {
        // Reverse-DNS folder names like "com.apple.Safari" should match against
        // the "safari" entry in the installed set.
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        #expect(classifier.isOrphanedAppSupport(folderName: "com.apple.Safari") == false)
    }

    @Test func isOrphanedAppSupportFlagsUnknownVendors() {
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        #expect(classifier.isOrphanedAppSupport(folderName: "com.deleted.vendor.oldapp") == true)
    }
}
