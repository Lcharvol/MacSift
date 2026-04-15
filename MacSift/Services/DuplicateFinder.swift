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
/// Each stage passes progress back via the optional callback so the UI
/// can show a determinate progress indicator rather than a silent spin.
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

    /// Progress callback shape: (phase, done, total).
    /// Phases are "sizing", "partialHash", "fullHash".
    typealias ProgressHandler = @Sendable (String, Int, Int) -> Void

    /// Main entry point. Returns every `DuplicateSet` with at least
    /// two members, sorted by `wastedBytes` descending (biggest wins
    /// first in the UI).
    static func findDuplicates(
        in files: [ScannedFile],
        minFileSize: Int64 = defaultMinFileSize,
        progress: ProgressHandler? = nil
    ) async -> [DuplicateSet] {
        // --- Stage 1: filter
        let candidates = files.filter { file in
            file.size >= minFileSize && dedupableCategories.contains(file.category)
        }
        progress?("sizing", 0, candidates.count)

        // --- Stage 2: group by size
        var bySize: [Int64: [ScannedFile]] = [:]
        for file in candidates {
            bySize[file.size, default: []].append(file)
        }
        let sameSizeGroups = bySize.values.filter { $0.count > 1 }
        let sameSizeCount = sameSizeGroups.reduce(0) { $0 + $1.count }
        progress?("sizing", sameSizeCount, candidates.count)

        guard !sameSizeGroups.isEmpty else { return [] }

        // --- Stage 3: partial hash (head + tail samples)
        var partialGroups: [[ScannedFile]] = []
        var partialDone = 0
        for group in sameSizeGroups {
            var byPartial: [String: [ScannedFile]] = [:]
            for file in group {
                let partial = partialHash(of: file.url, fileSize: file.size)
                byPartial[partial, default: []].append(file)
                partialDone += 1
                progress?("partialHash", partialDone, sameSizeCount)
            }
            for sub in byPartial.values where sub.count > 1 {
                partialGroups.append(sub)
            }
        }
        guard !partialGroups.isEmpty else { return [] }

        // --- Stage 4: full SHA-256 on survivors
        let fullTotal = partialGroups.reduce(0) { $0 + $1.count }
        var fullDone = 0
        var results: [DuplicateSet] = []
        for group in partialGroups {
            var byFull: [String: [ScannedFile]] = [:]
            for file in group {
                let full = fullHash(of: file.url)
                byFull[full, default: []].append(file)
                fullDone += 1
                progress?("fullHash", fullDone, fullTotal)
            }
            for (hash, members) in byFull where members.count > 1 {
                results.append(DuplicateSet(
                    id: hash,
                    size: members[0].size,
                    files: members
                ))
            }
        }

        return results.sorted { $0.wastedBytes > $1.wastedBytes }
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
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Full SHA-256 of the file, streamed in 64 KB chunks so we don't
    /// slurp multi-GB movies into memory. Returns a sentinel string on
    /// I/O errors so unreadable files get grouped separately (and
    /// therefore never match a readable peer).
    private static func fullHash(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "unreadable:\(url.path(percentEncoded: false))"
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}
