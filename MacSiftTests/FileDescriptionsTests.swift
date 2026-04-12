import Testing
import Foundation
@testable import MacSift

@Suite("FileDescriptions")
struct FileDescriptionsTests {
    @Test func describesCacheFiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Caches/com.apple.Safari")
        let desc = FileDescriptions.describe(url: url, category: .cache)
        #expect(desc.contains("Safari"))
    }

    @Test func describesLogFiles() {
        let url = URL(filePath: "/private/var/log/system.log")
        let desc = FileDescriptions.describe(url: url, category: .logs)
        #expect(desc.contains("System log"))
    }

    @Test func describesIOSBackup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Application Support/MobileSync/Backup/abc123")
        let desc = FileDescriptions.describe(url: url, category: .iosBackups)
        #expect(desc.contains("iOS"))
    }

    @Test func fallsBackToGenericDescription() {
        let url = URL(filePath: "/tmp/random_file.dat")
        let desc = FileDescriptions.describe(url: url, category: .tempFiles)
        #expect(!desc.isEmpty)
    }
}
