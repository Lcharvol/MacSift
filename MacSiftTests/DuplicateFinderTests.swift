import Testing
import Foundation
import CryptoKit
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
    // MARK: - Parallelization / cancellation / hex encoding
    //
    // Added alongside the bounded-concurrency rewrite of stages 3 and 4.

    /// (a) Identical files are still detected after parallelization.
    /// Uses enough distinct duplicate sets to exceed `hashConcurrency`
    /// so the task group's sliding window actually wraps around, and
    /// asserts every set is found with the right membership.
    @Test func identicalFilesStillDetectedWithParallelHashing() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let setCount = DuplicateFinder.hashConcurrency * 3
        var files: [ScannedFile] = []
        for setIndex in 0..<setCount {
            // Distinct size per set so stage 2 keeps them apart, and
            // distinct content so stage 4 must agree within the set.
            let payload = Data(repeating: UInt8(setIndex % 251), count: 1_100_000 + setIndex)
            for copy in 0..<3 {
                files.append(try makeFile(
                    in: tempDir,
                    name: "set\(setIndex)-copy\(copy).bin",
                    contents: payload
                ))
            }
        }
        // Shuffle so completion order never matches input order.
        files.shuffle()

        let result = await DuplicateFinder.findDuplicates(in: files)
        #expect(result.count == setCount)
        for set in result {
            #expect(set.count == 3, "every set had exactly 3 identical copies")
            // All members of a set must really share one size.
            #expect(Set(set.files.map(\.size)).count == 1)
        }
    }

    /// (b) Same-size, different-content files are NOT reported as
    /// duplicates. This is the false-positive guard — a false positive
    /// here means the UI offers to trash a file that is not a copy.
    /// The payloads differ only in the MIDDLE, so the head+tail partial
    /// hash matches and stage 4 is what has to separate them.
    @Test func sameSizeDifferentContentIsNotADuplicate() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let size = 2_000_000
        var a = Data(repeating: 0x5A, count: size)
        var b = Data(repeating: 0x5A, count: size)
        a[size / 2] = 0x01
        b[size / 2] = 0x02
        #expect(a.count == b.count, "precondition: identical sizes")
        #expect(a.prefix(4096) == b.prefix(4096), "precondition: identical heads")
        #expect(a.suffix(4096) == b.suffix(4096), "precondition: identical tails")

        let f1 = try makeFile(in: tempDir, name: "mid-a.bin", contents: a)
        let f2 = try makeFile(in: tempDir, name: "mid-b.bin", contents: b)

        let result = await DuplicateFinder.findDuplicates(in: [f1, f2])
        #expect(result.isEmpty, "differing middle bytes must not be reported as duplicates")
    }

    /// (c) A cancelled run returns no partial sets. Cancellation is
    /// signalled via the `isCancelled` predicate, which is how a
    /// detached caller must do it (`Task.detached` does not inherit
    /// cancellation from its parent).
    @Test func cancelledRunReturnsNoPartialSets() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Several real duplicate sets that WOULD be reported if the
        // run were allowed to finish.
        var files: [ScannedFile] = []
        for setIndex in 0..<6 {
            let payload = Data(repeating: UInt8(setIndex), count: 1_200_000 + setIndex)
            for copy in 0..<2 {
                files.append(try makeFile(
                    in: tempDir,
                    name: "c\(setIndex)-\(copy).bin",
                    contents: payload
                ))
            }
        }
        // Sanity: without cancellation these are all found.
        let baseline = await DuplicateFinder.findDuplicates(in: files)
        #expect(baseline.count == 6, "precondition: all sets found when not cancelled")

        // Now cancel immediately — before any hashing can complete.
        let cancelledResult = await DuplicateFinder.findDuplicates(
            in: files,
            isCancelled: { true }
        )
        #expect(
            cancelledResult.isEmpty,
            "a cancelled run must return nothing — partial sets must never look complete"
        )
    }

    /// (c-ii) Cancellation mid-flight (after some hashes have already
    /// landed) also yields nothing rather than the sets completed so far.
    @Test func cancellationPartWayThroughStillReturnsNothing() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var files: [ScannedFile] = []
        for setIndex in 0..<40 {
            let payload = Data(repeating: UInt8(setIndex % 251), count: 1_100_000 + setIndex)
            for copy in 0..<2 {
                files.append(try makeFile(
                    in: tempDir,
                    name: "m\(setIndex)-\(copy).bin",
                    contents: payload
                ))
            }
        }

        // Flip to cancelled after a handful of hash completions, so the
        // run is genuinely interrupted rather than never started.
        let counter = Counter()
        let result = await DuplicateFinder.findDuplicates(
            in: files,
            isCancelled: { counter.increment() > 50 }
        )
        #expect(result.isEmpty, "interrupted run must not surface the sets it already finished")
    }

    /// Thread-safe call counter for the cancellation predicate, which
    /// is polled from several hashing tasks at once.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    /// (d) The new hex encoding produces exactly the same digest
    /// strings as the old `String(format: "%02x")` implementation.
    @Test func hexEncodingMatchesStringFormatImplementation() {
        func legacyHex(_ bytes: [UInt8]) -> String {
            bytes.compactMap { String(format: "%02x", $0) }.joined()
        }

        // Every single byte value — covers zero-padding (0x00..0x0F)
        // and the a-f range, which is where a hand-rolled table is
        // most likely to go wrong.
        for byte in UInt8.min...UInt8.max {
            #expect([byte].hexString == legacyHex([byte]), "byte \(byte) encoded differently")
        }

        // Real SHA-256 digests.
        for sample in ["", "a", "hello world", "MacSift", String(repeating: "x", count: 10_000)] {
            let digest = SHA256.hash(data: Data(sample.utf8))
            let new = digest.hexString
            let old = legacyHex(Array(digest))
            #expect(new == old)
            #expect(new.count == 64, "SHA-256 hex is always 64 chars")
        }

        // Known-answer test: SHA-256 of the empty string.
        #expect(
            SHA256.hash(data: Data()).hexString
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    /// The progress callback must not fire once per file. With many
    /// files the throttle should keep the per-phase emission count far
    /// below the file count (forced first/last updates aside).
    @Test func progressIsThrottledNotPerFile() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var files: [ScannedFile] = []
        for setIndex in 0..<30 {
            let payload = Data(repeating: UInt8(setIndex % 251), count: 1_050_000 + setIndex)
            for copy in 0..<2 {
                files.append(try makeFile(
                    in: tempDir,
                    name: "p\(setIndex)-\(copy).bin",
                    contents: payload
                ))
            }
        }

        let recorder = PhaseRecorder()
        let result = await DuplicateFinder.findDuplicates(
            in: files,
            progress: { phase, done, total in recorder.record(phase, done, total) }
        )
        #expect(result.count == 30, "throttling must not change the outcome")

        let fullHashCalls = recorder.count(for: "fullHash")
        #expect(fullHashCalls > 0, "the handler is still wired up")
        // 60 files in the fullHash phase; a per-file callback would be
        // ~60 calls. Throttled to ~4/sec plus forced first/last, this
        // stays tiny for a sub-second run.
        #expect(
            fullHashCalls < 60,
            "fullHash fired \(fullHashCalls) times for 60 files — throttle is not working"
        )
        // The phase must still land on 100% so a determinate bar completes.
        let last = recorder.last(for: "fullHash")
        #expect(last?.done == last?.total, "final update must report done == total")
    }

    /// Thread-safe recorder for progress callbacks, which arrive from
    /// arbitrary hashing tasks.
    private final class PhaseRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(phase: String, done: Int, total: Int)] = []

        func record(_ phase: String, _ done: Int, _ total: Int) {
            lock.lock()
            defer { lock.unlock() }
            calls.append((phase, done, total))
        }

        func count(for phase: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return calls.filter { $0.phase == phase }.count
        }

        func last(for phase: String) -> (phase: String, done: Int, total: Int)? {
            lock.lock()
            defer { lock.unlock() }
            return calls.last { $0.phase == phase }
        }
    }

}
