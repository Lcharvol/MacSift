import Testing
import Foundation
@testable import MacSift

@Suite("DuplicateFinder")
struct DuplicateFinderTests {
    /// Build a tmp directory, write a file with the given contents,
    /// wrap it as a ScannedFile at the chosen category. Returns the
    /// file URL (so the test can clean up) alongside the
    /// ScannedFile that'll go into the finder.
    private func makeFile(
        in tempDir: URL,
        name: String,
        contents: Data,
        category: FileCategory = .largeFiles
    ) throws -> ScannedFile {
        let url = tempDir.appending(path: name)
        try contents.write(to: url)
        return ScannedFile(
            url: url,
            size: Int64(contents.count),
            category: category,
            description: "",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "DuplicateFinderTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func emptyInputReturnsEmptyOutput() async {
        let result = await DuplicateFinder.findDuplicates(in: [])
        #expect(result.isEmpty)
    }

    @Test func uniqueFilesProduceNoDuplicateSets() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Same size, different content → partial hash catches them.
        // Use 2 MB each so they pass the 1 MB minimum.
        let a = try makeFile(in: tempDir, name: "a.bin", contents: Data(repeating: 0xAA, count: 2_000_000))
        let b = try makeFile(in: tempDir, name: "b.bin", contents: Data(repeating: 0xBB, count: 2_000_000))

        let result = await DuplicateFinder.findDuplicates(in: [a, b])
        #expect(result.isEmpty)
    }

    @Test func twoIdenticalFilesFormOneSet() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0xCC, count: 2_000_000)
        let a = try makeFile(in: tempDir, name: "copy1.bin", contents: payload)
        let b = try makeFile(in: tempDir, name: "copy2.bin", contents: payload)

        let result = await DuplicateFinder.findDuplicates(in: [a, b])
        #expect(result.count == 1)
        let set = try #require(result.first)
        #expect(set.count == 2)
        #expect(set.size == 2_000_000)
        #expect(set.wastedBytes == 2_000_000)
    }

    @Test func threeIdenticalFilesFormOneSetWithDoubleWaste() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0xDD, count: 1_500_000)
        let a = try makeFile(in: tempDir, name: "a.bin", contents: payload)
        let b = try makeFile(in: tempDir, name: "b.bin", contents: payload)
        let c = try makeFile(in: tempDir, name: "c.bin", contents: payload)

        let result = await DuplicateFinder.findDuplicates(in: [a, b, c])
        #expect(result.count == 1)
        let set = try #require(result.first)
        #expect(set.count == 3)
        #expect(set.wastedBytes == Int64(payload.count) * 2)
    }

    @Test func filesBelowMinSizeAreSkipped() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 500 KB each — below the 1 MB default threshold.
        let payload = Data(repeating: 0xEE, count: 500_000)
        let a = try makeFile(in: tempDir, name: "small1.bin", contents: payload)
        let b = try makeFile(in: tempDir, name: "small2.bin", contents: payload)

        let result = await DuplicateFinder.findDuplicates(in: [a, b])
        #expect(result.isEmpty)
    }

    @Test func filesInNonDedupableCategoriesAreSkipped() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let payload = Data(repeating: 0xFF, count: 2_000_000)
        let a = try makeFile(in: tempDir, name: "a.cache", contents: payload, category: .cache)
        let b = try makeFile(in: tempDir, name: "b.cache", contents: payload, category: .cache)

        let result = await DuplicateFinder.findDuplicates(in: [a, b])
        #expect(result.isEmpty, "Caches must never be deduped — they're expected to differ between machines")
    }

    @Test func wastedBytesOnSingleFileSetIsZero() {
        let file = ScannedFile(
            url: URL(filePath: "/tmp/a.bin"),
            size: 1_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: .now,
            isDirectory: false
        )
        let set = DuplicateSet(id: "abc", size: 1_000_000, files: [file])
        #expect(set.wastedBytes == 0)
    }

    @Test func resultsAreSortedByWastedBytesDescending() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Small set (2 copies × 1.2 MB = 1.2 MB wasted)
        let smallPayload = Data(repeating: 0x01, count: 1_200_000)
        let s1 = try makeFile(in: tempDir, name: "small1.bin", contents: smallPayload)
        let s2 = try makeFile(in: tempDir, name: "small2.bin", contents: smallPayload)

        // Large set (2 copies × 3 MB = 3 MB wasted)
        let largePayload = Data(repeating: 0x02, count: 3_000_000)
        let l1 = try makeFile(in: tempDir, name: "large1.bin", contents: largePayload)
        let l2 = try makeFile(in: tempDir, name: "large2.bin", contents: largePayload)

        let result = await DuplicateFinder.findDuplicates(in: [s1, s2, l1, l2])
        #expect(result.count == 2)
        // Largest waste first.
        #expect(result[0].wastedBytes > result[1].wastedBytes)
    }
}
