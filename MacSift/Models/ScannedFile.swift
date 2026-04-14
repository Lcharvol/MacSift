import Foundation
import CryptoKit

struct ScannedFile: Identifiable, Hashable, Sendable {
    /// Stable id derived from the file's absolute path. Re-scans of the same
    /// file produce the same id, so the user's selection survives a refresh.
    let id: String
    let url: URL
    let size: Int64
    let category: FileCategory
    let description: String
    let modificationDate: Date
    let isDirectory: Bool
    /// Volume this file lives on. Stamped at scan time so the UI can filter
    /// by source (Macintosh HD, external drives) without re-walking URLs.
    /// Uses the volume's path-based id, e.g. "/" or "/Volumes/Samsung T7".
    let volumeID: String

    init(
        url: URL,
        size: Int64,
        category: FileCategory,
        description: String,
        modificationDate: Date,
        isDirectory: Bool,
        volumeID: String = Volume.bootVolumeID
    ) {
        self.id = Self.stableID(for: url)
        self.url = url
        self.size = size
        self.category = category
        self.description = description
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.volumeID = volumeID
    }

    private static func stableID(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path(percentEncoded: false)
    }
}
