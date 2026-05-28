import Foundation

/// Display-only aggregation of one or more `ScannedFile`s that belong to the
/// same logical owner — typically an app's cache folder, an iOS backup, or
/// a single standalone large file. Selection still happens at the underlying
/// `ScannedFile` level so cleaning is unchanged.
struct FileGroup: Identifiable, Hashable, Sendable {
    /// Stable id derived from the group's representative path.
    let id: String
    let label: String
    let category: FileCategory
    let totalSize: Int64
    let fileCount: Int
    /// All files contained in this group. For singleton groups this has one element.
    let files: [ScannedFile]
    /// Pre-computed top 5 largest files for the inspector. Avoids re-sorting
    /// the full `files` array on every render.
    let topFiles: [ScannedFile]
    /// Pre-computed most recent modification date across all files in this
    /// group. Used by the "Most Recent" sort option without walking files.
    let mostRecentModificationDate: Date
    /// Best representative URL for "Reveal in Finder" style actions.
    let representativeURL: URL
    /// Set of underlying file ids — used for selection roll-up. Stored, not
    /// computed: `FileListSection` reads it once per visible row on every
    /// render, and rebuilding the Set per access turned every selection
    /// toggle into O(sum of all visible group sizes) of hash work on the
    /// main thread. Built once in `FileGrouper` and shared by all renders.
    let fileIDs: Set<String>
    /// True when this group contains more than one file. Used by the UI to
    /// decide whether to show a count badge / drill-down affordance.
    var isAggregated: Bool { fileCount > 1 }
}
