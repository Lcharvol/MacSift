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

    // MARK: - Xcode Junk

    @Test func classifiesXcodeDerivedData() {
        let url = home.appending(path: "Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug/MyApp.app/MyApp")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesXcodeArchives() {
        let url = home.appending(path: "Library/Developer/Xcode/Archives/2025-11-01/MyApp 2025-11-01 10.00.xcarchive/Info.plist")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesIOSDeviceSupport() {
        let url = home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)/Symbols/usr/lib/dyld")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesCoreSimulatorCaches() {
        let url = home.appending(path: "Library/Developer/CoreSimulator/Caches/dyld/abc123/dyld_shared_cache_arm64e")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    // MARK: - Dev Caches

    @Test func classifiesNpmCache() {
        let url = home.appending(path: ".npm/_cacache/content-v2/sha512/ab/cd.gz")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesHomebrewCache() {
        let url = home.appending(path: "Library/Caches/Homebrew/downloads/ffmpeg.tar.gz")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesGoModuleCache() {
        let url = home.appending(path: "go/pkg/mod/github.com/foo/bar/baz.go")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesCargoRegistryCache() {
        let url = home.appending(path: ".cargo/registry/cache/index.crates.io-abc/tokio-1.0.0.crate")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    // MARK: - Old Downloads

    @Test func classifiesOldDownloadAsOldDownloads() {
        let url = home.appending(path: "Downloads/Some-installer.dmg")
        let oldDate = Date().addingTimeInterval(-100 * 86400)  // 100 days ago
        #expect(classifier.classify(url: url, size: 1000, modificationDate: oldDate) == .oldDownloads)
    }

    @Test func doesNotClassifyRecentDownloadAsOld() {
        let url = home.appending(path: "Downloads/Recent.pdf")
        let recentDate = Date().addingTimeInterval(-5 * 86400)  // 5 days ago
        #expect(classifier.classify(url: url, size: 1000, modificationDate: recentDate) == nil)
    }

    @Test func recentLargeDownloadClassifiesAsLargeFiles() {
        // Regression: previously a recent file in ~/Downloads returned nil
        // regardless of size. After the double-count fix, recent files fall
        // through to the .largeFiles check and big ones are still flagged.
        let url = home.appending(path: "Downloads/RecentInstaller.dmg")
        let recent = Date().addingTimeInterval(-5 * 86400)
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1, modificationDate: recent) == .largeFiles)
    }

    @Test func oldLargeDownloadPrefersOldDownloads() {
        // A file that matches both .oldDownloads (age) and .largeFiles (size)
        // should be classified as .oldDownloads — that check runs first.
        let url = home.appending(path: "Downloads/OldBigVideo.mov")
        let old = Date().addingTimeInterval(-200 * 86400)
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1, modificationDate: old) == .oldDownloads)
    }

    // MARK: - Mail Attachments

    @Test func classifiesMailDownloads() {
        let url = home.appending(path: "Library/Mail Downloads/abc123/attachment.pdf")
        #expect(classifier.classify(url: url, size: 1000) == .mailDownloads)
    }

    @Test func classifiesMailContainerDownloads() {
        let url = home.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/xyz/photo.jpg")
        #expect(classifier.classify(url: url, size: 1000) == .mailDownloads)
    }
}
