import Foundation
import CryptoKit

/// Finds byte-identical files in a pre-scanned list. Pipeline:
///
/// 1. **Filter** by size and category: only files ≥ `minFileSize` and
///    in a category that looks like user data (no caches/logs/derived
///    artifacts — those are expected to differ between machines and
///    running apps, and collisions there are noise, not waste).
/// 2. **Group by size**. Files with a unique size can't have a
///    content duplicate, so they drop out immediately. This is O(n)
///    and typically filters 95%+ of the candidates on a real machine.
/// 3. **Partial-hash collision** (first 4 KB + last 4 KB, SHA-256).
///    Cheap — a few disk seeks per file — but catches almost every
///    same-size-different-content pair. Survivors are the only files
///    we'll ever read in full.
/// 4. **Full SHA-256** on the remaining candidates. Only files that
///    survived steps 1-3 get hashed end-to-end. The final SHA is the
///    identifier for the `DuplicateSet`.
///
/// Stages 3 and 4 hash files **concurrently** through a bounded task
/// group (see `hashConcurrency`), and every stage is **cooperatively
/// cancellable** — including the chunk loop inside `fullHash`, so a
/// single multi-GB file can be abandoned mid-read.
///
/// Each stage passes progress back via the optional callback so the UI
/// can show a determinate progress indicator rather than a silent spin.
/// The callback is **throttled** (see `progressThrottle`) so it can
/// never fire once per file.
enum DuplicateFinder {
    /// Ignore files smaller than this. 1 MB is small enough that real
    /// user-data duplicates (downloaded files, photos, installers,
    /// archives) are caught while cheap system-file noise is skipped.
    static let defaultMinFileSize: Int64 = 1_048_576

    /// Categories we consider "user data" and therefore worth
    /// dedup-checking. Everything else is either expected to differ
    /// (caches, logs, temp files, build artifacts) or impossible to
    /// usefully dedupe (Time Machine snapshots have a synthetic URL).
    static let dedupableCategories: Set<FileCategory> = [
        .largeFiles,
        .oldDownloads,
        .mailDownloads,
    ]

    /// How many files we hash at once.
    ///
    /// Hashing a file is a *blocking* `read(2)` loop on a cooperative
    /// executor thread, so this bound is doing two jobs: it buys
    /// overlap between I/O and SHA-256 computation, and it stops us
    /// from parking every thread in the cooperative pool on a blocking
    /// syscall (the pool is sized to `activeProcessorCount`, so
    /// spawning one task per file would starve everything else in the
    /// app — the same oversubscription bug being fixed in
    /// `DiskScanner`).
    ///
    /// `activeProcessorCount` clamped to 4...8 is a deliberately
    /// conservative middle ground. On one APFS volume the full-hash
    /// stage is bandwidth-bound, not latency-bound: reading four
    /// multi-GB files at once does not quadruple throughput, it mostly
    /// keeps the device queue busy while SHA-256 runs on the previous
    /// chunk. The real win is the **partial-hash** stage, which is
    /// thousands of independent 4 KB seeks — those overlap beautifully
    /// and that stage is where a wide candidate list actually hurts.
    /// Going much above 8 risks thrashing the read-ahead heuristics and
    /// (on a spinning disk or network volume) making things slower.
    static var hashConcurrency: Int {
        min(max(ProcessInfo.processInfo.activeProcessorCount, 4), 8)
    }

    /// Minimum wall-clock gap between two `ProgressHandler` calls for
    /// the same phase. CLAUDE.md lesson #11: throttle UI updates to
    /// ~4/sec. The final tally of each stage is always delivered, so a
    /// caller driving a determinate progress bar still lands on 100%.
    static let progressThrottle: Duration = .milliseconds(250)

    /// Progress callback shape: (phase, done, total).
    /// Phases are "sizing", "partialHash", "fullHash".
    ///
    /// Called at most ~4×/sec per phase (plus one final call per
    /// phase). May be invoked from any thread/task — it is `@Sendable`
    /// and callers that touch UI state must hop to the main actor
    /// themselves.
    typealias ProgressHandler = @Sendable (String, Int, Int) -> Void

    /// Main entry point. Returns every `DuplicateSet` with at least
    /// two members, sorted by `wastedBytes` descending (biggest wins
    /// first in the UI).
    ///
    /// ## Cancellation
    ///
    /// Returns an **empty array** if the task is cancelled at any
    /// point. This is deliberate and load-bearing: the UI offers
    /// "keep the oldest, trash the rest", so a half-finished run must
    /// never be presented as a complete answer. A group whose hashing
    /// was interrupted could be missing the very member the user would
    /// have chosen to keep, and showing it would invite data loss.
    /// Empty means "we don't know", which the UI already renders as
    /// "no duplicates found" — safe, if mildly disappointing.
    ///
    /// - Important: `Task.detached` does **not** inherit cancellation
    ///   from its parent. If you call this from a detached task (as
    ///   `ScanViewModel` does) you must forward cancellation yourself,
    ///   either by cancelling that detached task directly or by
    ///   passing `isCancelled`.
    /// - Parameter isCancelled: Optional extra cancellation predicate,
    ///   OR-ed with `Task.isCancelled`. Lets a caller that cannot
    ///   structurally propagate cancellation (a detached task) still
    ///   stop the work. Polled frequently; keep it cheap.
    static func findDuplicates(
        in files: [ScannedFile],
        minFileSize: Int64 = defaultMinFileSize,
        progress: ProgressHandler? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async -> [DuplicateSet] {
        let cancelled: @Sendable () -> Bool = {
            Task.isCancelled || (isCancelled?() ?? false)
        }
        let reporter = progress.map { ProgressReporter(handler: $0) }

        // --- Stage 1: filter
        let candidates = files.filter { file in
            file.size >= minFileSize && dedupableCategories.contains(file.category)
        }
        guard !cancelled() else { return [] }
        await reporter?.report("sizing", 0, candidates.count, force: true)

        // --- Stage 2: group by size
        var bySize: [Int64: [ScannedFile]] = [:]
        for file in candidates {
            bySize[file.size, default: []].append(file)
        }
        let sameSizeGroups = bySize.values.filter { $0.count > 1 }
        let sameSizeCount = sameSizeGroups.reduce(0) { $0 + $1.count }
        await reporter?.report("sizing", sameSizeCount, candidates.count, force: true)

        guard !sameSizeGroups.isEmpty else { return [] }
        guard !cancelled() else { return [] }

        // --- Stage 3: partial hash (head + tail samples)
        //
        // Flatten every same-size group into one work list so the task
        // group stays saturated: otherwise a group of 2 would only ever
        // use 2 of our workers. Each file carries the id of the size
        // group it came from, and we only ever compare partial hashes
        // *within* that group — flattening is purely a scheduling
        // change, not a semantic one.
        let partialWork: [(group: Int, file: ScannedFile)] = sameSizeGroups
            .enumerated()
            .flatMap { index, group in group.map { (group: index, file: $0) } }

        let partialHashes = await concurrentMap(
            partialWork,
            phase: "partialHash",
            reporter: reporter,
            cancelled: cancelled
        ) { item in
            partialHash(of: item.file.url, fileSize: item.file.size)
        }
        guard let partialHashes else { return [] }

        // Re-bucket by (size group, partial hash). Keyed on the group
        // index as well as the hash so two files of *different* sizes
        // can never land in the same bucket.
        var byPartial: [PartialKey: [ScannedFile]] = [:]
        for (item, hash) in zip(partialWork, partialHashes) {
            byPartial[PartialKey(group: item.group, hash: hash), default: []].append(item.file)
        }
        let partialGroups = byPartial.values.filter { $0.count > 1 }
        guard !partialGroups.isEmpty else { return [] }
        guard !cancelled() else { return [] }

        // --- Stage 4: full SHA-256 on survivors
        let fullWork: [(group: Int, file: ScannedFile)] = partialGroups
            .enumerated()
            .flatMap { index, group in group.map { (group: index, file: $0) } }

        let fullHashes = await concurrentMap(
            fullWork,
            phase: "fullHash",
            reporter: reporter,
            cancelled: cancelled
        ) { item in
            fullHash(of: item.file.url, isCancelled: cancelled)
        }
        guard let fullHashes else { return [] }

        var byFull: [PartialKey: [ScannedFile]] = [:]
        for (item, hash) in zip(fullWork, fullHashes) {
            byFull[PartialKey(group: item.group, hash: hash), default: []].append(item.file)
        }

        var results: [DuplicateSet] = []
        for (key, members) in byFull where members.count > 1 {
            results.append(DuplicateSet(
                id: key.hash,
                size: members[0].size,
                files: members
            ))
        }

        return results.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    /// Bucket key for stages 3 and 4: a content hash scoped to the
    /// candidate group it was computed in.
    private struct PartialKey: Hashable {
        let group: Int
        let hash: String
    }

    // MARK: - Bounded concurrency

    /// Hash `items` through a task group capped at `hashConcurrency`,
    /// preserving input order in the returned array.
    ///
    /// Returns `nil` if the work was cancelled — callers treat that as
    /// "abandon the whole run" rather than using a partial result.
    ///
    /// The sliding-window pattern (prime N tasks, then add one more
    /// each time one finishes) is what keeps this *bounded*: a plain
    /// `for item in items { group.addTask { … } }` would enqueue one
    /// blocking read per file and park the entire cooperative pool.
    private static func concurrentMap(
        _ items: [(group: Int, file: ScannedFile)],
        phase: String,
        reporter: ProgressReporter?,
        cancelled: @escaping @Sendable () -> Bool,
        transform: @escaping @Sendable ((group: Int, file: ScannedFile)) -> String
    ) async -> [String]? {
        let total = items.count
        guard total > 0 else { return [] }

        await reporter?.report(phase, 0, total, force: true)

        var results = [String?](repeating: nil, count: total)
        var done = 0
        var wasCancelled = false

        await withTaskGroup(of: (Int, String)?.self) { group in
            let limit = min(hashConcurrency, total)
            var next = 0

            // Prime the window.
            while next < limit {
                let index = next
                let item = items[index]
                group.addTask {
                    guard !cancelled() else { return nil }
                    return (index, transform(item))
                }
                next += 1
            }

            while let finished = await group.next() {
                guard let (index, hash) = finished else {
                    // A worker observed cancellation. Stop feeding the
                    // group and let the in-flight tasks drain.
                    wasCancelled = true
                    group.cancelAll()
                    continue
                }
                results[index] = hash
                done += 1
                await reporter?.report(phase, done, total)

                if cancelled() {
                    wasCancelled = true
                    group.cancelAll()
                    continue
                }
                if next < total {
                    let index = next
                    let item = items[index]
                    group.addTask {
                        guard !cancelled() else { return nil }
                        return (index, transform(item))
                    }
                    next += 1
                }
            }
        }

        if wasCancelled || cancelled() { return nil }
        await reporter?.report(phase, total, total, force: true)

        // Every slot is filled on a non-cancelled run; the compactMap
        // is a belt-and-braces guard, and a short count is treated as
        // cancellation rather than silently dropping a candidate.
        let unwrapped = results.compactMap { $0 }
        return unwrapped.count == total ? unwrapped : nil
    }

    /// Serializes and rate-limits `ProgressHandler` calls.
    ///
    /// An actor because stage 3/4 workers finish on arbitrary threads;
    /// without it the handler would race. Cheap: one `await` per
    /// completed file, no I/O.
    private actor ProgressReporter {
        private let handler: ProgressHandler
        private var lastEmit: [String: ContinuousClock.Instant] = [:]
        private let clock = ContinuousClock()

        init(handler: @escaping ProgressHandler) {
            self.handler = handler
        }

        /// - Parameter force: bypass the throttle. Used for the first
        ///   and last update of each phase so a determinate progress
        ///   bar always starts at 0 and ends at `total`.
        func report(_ phase: String, _ done: Int, _ total: Int, force: Bool = false) {
            let now = clock.now
            if !force, let last = lastEmit[phase], now - last < progressThrottle {
                return
            }
            lastEmit[phase] = now
            handler(phase, done, total)
        }
    }

    // MARK: - Hash helpers

    /// Hash the first and last 4 KB of the file, concatenated. Cheap
    /// fingerprint that's very unlikely to collide across different
    /// contents. For files smaller than 8 KB, we hash the whole thing.
    private static func partialHash(of url: URL, fileSize: Int64) -> String {
        let sampleSize: Int64 = 4096
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "unreadable:\(fileSize)"
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        if fileSize <= sampleSize * 2 {
            if let data = try? handle.readToEnd() {
                hasher.update(data: data)
            }
        } else {
            if let head = try? handle.read(upToCount: Int(sampleSize)) {
                hasher.update(data: head)
            }
            try? handle.seek(toOffset: UInt64(fileSize - sampleSize))
            if let tail = try? handle.read(upToCount: Int(sampleSize)) {
                hasher.update(data: tail)
            }
        }
        return hasher.finalize().hexString
    }

    /// Full SHA-256 of the file, streamed in 64 KB chunks so we don't
    /// slurp multi-GB movies into memory. Returns a sentinel string on
    /// I/O errors so unreadable files get grouped separately (and
    /// therefore never match a readable peer).
    ///
    /// Checks cancellation every chunk: a single 50 GB file has to be
    /// abandonable, otherwise cancelling the scan still waits out the
    /// whole read. Cancelled reads return a unique sentinel so the
    /// partial digest can never be mistaken for a real hash and match
    /// a peer — belt and braces, since `concurrentMap` discards the
    /// whole run on cancellation anyway.
    private static func fullHash(
        of url: URL,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "unreadable:\(url.path(percentEncoded: false))"
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            if isCancelled() {
                return "cancelled:\(UUID().uuidString)"
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}

// MARK: - Fast hex encoding

extension Sequence<UInt8> {
    /// Lowercase hex string, one allocation.
    ///
    /// Replaces `compactMap { String(format: "%02x", $0) }.joined()`,
    /// which built a `String` *per byte* (32 of them per SHA-256) and
    /// paid `String(format:)`'s printf-parsing cost each time. This
    /// does a table lookup into a reserved `String` instead.
    var hexString: String {
        let digits: [Character] = [
            "0", "1", "2", "3", "4", "5", "6", "7",
            "8", "9", "a", "b", "c", "d", "e", "f",
        ]
        var out = ""
        out.reserveCapacity(64)
        for byte in self {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }
}
