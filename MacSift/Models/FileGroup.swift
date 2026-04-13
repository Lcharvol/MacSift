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
    /// True when this group contains more than one file. Used by the UI to
    /// decide whether to show a count badge / drill-down affordance.
    var isAggregated: Bool { fileCount > 1 }

    /// Set of underlying file ids — used for selection roll-up.
    var fileIDs: Set<String> {
        Set(files.map(\.id))
    }
}
