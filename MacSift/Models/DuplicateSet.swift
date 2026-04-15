import Foundation

/// A set of `ScannedFile`s whose content is byte-identical. Built by
/// `DuplicateFinder` — every member has the same size and verified
/// SHA-256 of the full file contents.
///
/// "Wasted bytes" is the metric that matters to the user: if you have
/// 3 copies of a 5 GB movie, keeping one is unavoidable, the other
/// two are the waste. Reclaimable = size × (count - 1).
struct DuplicateSet: Identifiable, Hashable, Sendable {
    /// The shared SHA-256 of every file in the set. Used as the
    /// identifier so SwiftUI ForEach can diff stably across scans.
    let id: String
    /// Bytes per file. Every member has this exact size.
    let size: Int64
    /// All members, in no particular order. The finder preserves the
    /// order in which files were encountered in the scan so that
    /// `files.first` is a stable "representative" across re-runs.
    let files: [ScannedFile]

    var count: Int { files.count }

    /// Bytes reclaimable by deleting every copy except the first one.
    /// Always non-negative.
    var wastedBytes: Int64 {
        guard files.count > 1 else { return 0 }
        return size * Int64(files.count - 1)
    }
}
