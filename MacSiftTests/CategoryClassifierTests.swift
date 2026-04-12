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
}
