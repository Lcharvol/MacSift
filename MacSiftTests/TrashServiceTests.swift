import Testing
import Foundation
@testable import MacSift

@Suite("TrashService")
struct TrashServiceTests {
    private func makeFakeTrash() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacSiftTrashTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try Data(repeating: 0xAA, count: bytes).write(to: url)
    }

    @Test func emptyDirectoryReportsZero() throws {
        let dir = try makeFakeTrash()
        defer { try? FileManager.default.removeItem(at: dir) }

        let summary = TrashService.summary(of: dir)
        #expect(summary.itemCount == 0)
        #expect(summary.totalSize == 0)
    }

    @Test func summarizesFilesAndSubdirectories() throws {
        let dir = try makeFakeTrash()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(dir.appending(path: "a.dat"), bytes: 1000)
        try writeFile(dir.appending(path: "b.dat"), bytes: 2000)

        // A subfolder with two files inside
        let subdir = dir.appending(path: "subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try writeFile(subdir.appending(path: "c.dat"), bytes: 500)
        try writeFile(subdir.appending(path: "d.dat"), bytes: 700)

        let summary = TrashService.summary(of: dir)
        // 3 top-level entries (a.dat, b.dat, subdir)
        #expect(summary.itemCount == 3)
        // Sizes are reported using allocated size on APFS, which rounds up
        // to the block size. Assert a reasonable lower bound instead of an
        // exact match so the test doesn't depend on APFS block sizes.
        #expect(summary.totalSize >= 1000 + 2000 + 500 + 700)
    }

    @Test func emptyDirectoryWipesEverything() throws {
        let dir = try makeFakeTrash()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeFile(dir.appending(path: "x.dat"), bytes: 100)
        try writeFile(dir.appending(path: "y.dat"), bytes: 100)

        #expect(TrashService.summary(of: dir).itemCount == 2)
        TrashService.emptyDirectory(dir)
        #expect(TrashService.summary(of: dir).itemCount == 0)
    }
}
