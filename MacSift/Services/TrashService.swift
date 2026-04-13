import Foundation

/// Minimal service to inspect and empty the user's Trash (`~/.Trash`).
/// MacSift moves files to the Trash via `FileManager.trashItem` — this
/// service completes the workflow by letting the user actually reclaim
/// the space when they're ready.
enum TrashService {
    struct Summary: Sendable {
        let itemCount: Int
        let totalSize: Int64
    }

    /// Walk ~/.Trash and return the number of items and their total size.
    /// Runs on the calling thread — callers should use `Task.detached` for
    /// responsiveness. Silently skips items we can't stat.
    static func summary() -> Summary {
        let fm = FileManager.default
        guard let trashURL = try? fm.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return Summary(itemCount: 0, totalSize: 0)
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: trashURL,
            includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
        ) else {
            return Summary(itemCount: 0, totalSize: 0)
        }

        var total: Int64 = 0
        for item in contents {
            total += sizeOf(url: item)
        }
        return Summary(itemCount: contents.count, totalSize: total)
    }

    /// Recursively size an item. Files return their fileSize; directories
    /// are walked and summed.
    private static func sizeOf(url: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }

        if values.isDirectory == true {
            var total: Int64 = 0
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else { return 0 }
            while let next = enumerator.nextObject() as? URL {
                if let nestedValues = try? next.resourceValues(forKeys: keys),
                   nestedValues.isDirectory != true
                {
                    total += Int64(nestedValues.totalFileAllocatedSize ?? nestedValues.fileAllocatedSize ?? 0)
                }
            }
            return total
        }

        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    /// Remove every top-level entry from the user's Trash. Returns the summary
    /// BEFORE deletion (what was freed). Errors on individual items are
    /// swallowed — we do best-effort deletion.
    @discardableResult
    static func empty() -> Summary {
        let fm = FileManager.default
        let before = summary()
        guard let trashURL = try? fm.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return before
        }

        if let contents = try? fm.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }
        return before
    }
}
