import Testing
import Foundation
@testable import MacSift

@Suite("CleaningEngine Integration")
struct CleaningEngineIntegrationTests {
    private func createTempFile(in dir: URL, name: String, size: Int) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: name)
        try Data(repeating: 0xFF, count: size).write(to: fileURL)
        return fileURL
    }

    private func makeScannedFile(url: URL, size: Int64) -> ScannedFile {
        ScannedFile(
            url: url,
            size: size,
            category: .cache,
            description: "Test file",
            modificationDate: .now,
            isDirectory: false
        )
    }

    @Test func deletesFilesSuccessfully() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = try createTempFile(in: tempDir, name: "delete_me.dat", size: 1024)
        let file = makeScannedFile(url: fileURL, size: 1024)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        #expect(report.deletedCount == 1)
        #expect(report.freedSize == 1024)
        #expect(report.failedFiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test func dryRunDoesNotDeleteFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = try createTempFile(in: tempDir, name: "keep_me.dat", size: 2048)
        let file = makeScannedFile(url: fileURL, size: 2048)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: true)

        #expect(report.deletedCount == 1)
        #expect(report.freedSize == 2048)
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test func handlesAlreadyDeletedFiles() async throws {
        let fileURL = URL(filePath: "/tmp/MacSiftCleanTest-nonexistent-\(UUID().uuidString).dat")
        let file = makeScannedFile(url: fileURL, size: 500)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        #expect(report.failedFiles.isEmpty)
    }

    @Test func handlesPermissionErrors() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = try createTempFile(in: tempDir, name: "locked.dat", size: 512)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tempDir.path(percentEncoded: false))

        let file = makeScannedFile(url: fileURL, size: 512)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        #expect(report.failedFiles.count == 1)
        #expect(report.deletedCount == 0)
    }
}
