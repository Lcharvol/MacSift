import Testing
import Foundation
@testable import MacSift

@Suite("FileDescriptions")
struct FileDescriptionsTests {
    private let english = Locale(identifier: "en")

    @Test func describesCacheFiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Caches/com.apple.Safari")
        let desc = FileDescriptions.describe(url: url, category: .cache, locale: english)
        #expect(desc.contains("Safari"))
    }

    @Test func describesLogFiles() {
        let url = URL(filePath: "/private/var/log/system.log")
        let desc = FileDescriptions.describe(url: url, category: .logs, locale: english)
        #expect(desc.contains("System log"))
    }

    @Test func describesIOSBackup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Application Support/MobileSync/Backup/abc123")
        let desc = FileDescriptions.describe(url: url, category: .iosBackups, locale: english)
        #expect(desc.contains("iOS"))
    }

    @Test func describesIOSBackupWithNonCanonicalCasing() {
        // macOS filesystems are case-insensitive by default, so the actual
        // path may use different casing than the canonical "MobileSync/Backup/".
        let url = URL(filePath: "/Users/test/Library/Application Support/mobilesync/backup/abc123")
        let desc = FileDescriptions.describe(url: url, category: .iosBackups, locale: english)
        #expect(desc.contains("iOS"))
    }

    @Test func fallsBackToGenericDescription() {
        let url = URL(filePath: "/tmp/random_file.dat")
        let desc = FileDescriptions.describe(url: url, category: .tempFiles, locale: english)
        #expect(!desc.isEmpty)
    }
}
