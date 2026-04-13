import Testing
import Foundation
@testable import MacSift

@Suite("FileDescriptions · iOS backups")
struct FileDescriptionsIOSBackupTests {
    private func makeTempBackup(deviceName: String?, productType: String?, date: Date?) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "MacSiftIOSBackupTest-\(UUID().uuidString)")
        let backupID = UUID().uuidString
        let backupRoot = tempDir.appending(path: "Library/Application Support/MobileSync/Backup/\(backupID)")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        // Write a minimal Info.plist with the requested fields
        var plist: [String: Any] = [:]
        if let deviceName { plist["Device Name"] = deviceName }
        if let productType { plist["Product Type"] = productType }
        if let date { plist["Last Backup Date"] = date }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: backupRoot.appending(path: "Info.plist"))
        return backupRoot
    }

    @Test func readsDeviceNameAndDateFromInfoPlist() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14
        let root = try makeTempBackup(deviceName: "Jane's iPhone", productType: "iPhone13,3", date: date)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let fileInside = root.appending(path: "Manifest.db")
        let description = FileDescriptions.describe(url: fileInside, category: .iosBackups)

        #expect(description.contains("iOS backup:"))
        #expect(description.contains("Jane's iPhone"))
    }

    @Test func fallsBackToProductTypeWhenDeviceNameMissing() throws {
        let root = try makeTempBackup(deviceName: nil, productType: "iPhone14,5", date: nil)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let fileInside = root.appending(path: "Manifest.db")
        let description = FileDescriptions.describe(url: fileInside, category: .iosBackups)

        #expect(description.contains("iPhone14,5"))
    }

    @Test func genericFallbackWhenNoPlist() {
        // URL that looks like a MobileSync backup but no Info.plist exists
        let nonexistentRoot = URL(filePath: "/tmp/nonexistent-MobileSync/Backup/fake-\(UUID().uuidString)")
        let file = nonexistentRoot.appending(path: "Manifest.db")
        let description = FileDescriptions.describe(url: file, category: .iosBackups)

        // Should still produce a non-empty description even if Info.plist is missing
        #expect(!description.isEmpty)
        #expect(description.lowercased().contains("ios"))
    }

    @Test func descriptionIsCached() throws {
        // Calling describe twice on files in the same backup root should
        // only parse Info.plist once. We can't directly assert cache hits,
        // but we can assert the output is identical.
        let root = try makeTempBackup(deviceName: "Cache Test Device", productType: nil, date: nil)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let file1 = root.appending(path: "Manifest.db")
        let file2 = root.appending(path: "Info.plist")

        let desc1 = FileDescriptions.describe(url: file1, category: .iosBackups)
        let desc2 = FileDescriptions.describe(url: file2, category: .iosBackups)

        #expect(desc1 == desc2)
        #expect(desc1.contains("Cache Test Device"))
    }
}
