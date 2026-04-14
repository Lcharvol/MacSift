import Foundation

/// A mounted volume we can scan (and potentially clean).
struct Volume: Identifiable, Hashable, Sendable {
    let id: String          // stable id: the volume URL path
    let url: URL
    let name: String        // user-facing name, e.g. "Samsung T7"
    let isBoot: Bool        // the boot volume — the one containing the user's home
    let isReadOnly: Bool
    /// Total bytes on the volume (for display). 0 if unknown.
    let totalCapacity: Int64
    /// Free bytes on the volume (for display). 0 if unknown.
    let availableCapacity: Int64

    /// Sentinel id used for the boot volume when we can't resolve one at
    /// construction time — in particular, legacy `ScannedFile` sites that
    /// don't pass a volumeID explicitly. Anything stamped with this id is
    /// treated as living on the boot volume.
    static let bootVolumeID = "/"
}

/// Discover mounted volumes eligible for scanning. Filters out system /
/// hidden volumes (Recovery, VM, Preboot, Update) and Time Machine
/// backup disks so the user doesn't accidentally try to clean them.
enum VolumeDiscovery {
    /// Return the boot volume plus any eligible external/secondary volumes.
    /// The boot volume is always first.
    static func list() -> [Volume] {
        let fm = FileManager.default
        var result: [Volume] = []

        // Boot volume — construct from the user home's parent volume.
        if let boot = bootVolume() {
            result.append(boot)
        }

        // External / secondary volumes under /Volumes/*. macOS exposes the
        // boot volume there too as a symlink, so we skip it if we already
        // added it above.
        let mountedKeys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsReadOnlyKey,
            .volumeIsBrowsableKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRootFileSystemKey,
        ]

        let mounted = fm.mountedVolumeURLs(includingResourceValuesForKeys: mountedKeys, options: [.skipHiddenVolumes]) ?? []
        let bootPath = result.first?.url.path(percentEncoded: false)

        for rawURL in mounted {
            let url = rawURL.resolvingSymlinksInPath()
            let path = url.path(percentEncoded: false)
            if path == bootPath { continue }              // already added
            if isBlocked(url: url) { continue }           // TM, Recovery, etc.
            guard let values = try? url.resourceValues(forKeys: Set(mountedKeys)) else { continue }
            guard values.volumeIsBrowsable == true else { continue }
            guard values.volumeIsRootFileSystem != true else { continue }  // boot under another guise
            let name = values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            let volume = Volume(
                id: path,
                url: url,
                name: name,
                isBoot: false,
                isReadOnly: values.volumeIsReadOnly ?? false,
                totalCapacity: total,
                availableCapacity: available
            )
            result.append(volume)
        }

        return result
    }

    /// Best effort: the volume that contains the user's home directory.
    private static func bootVolume() -> Volume? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey,
        ]
        guard let values = try? home.resourceValues(forKeys: keys),
              let volumeURL = values.volume else {
            return nil
        }
        let name = (try? volumeURL.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
        let total = Int64((try? volumeURL.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity) ?? 0)
        let available = Int64((try? volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity) ?? 0)
        return Volume(
            id: volumeURL.path(percentEncoded: false),
            url: volumeURL,
            name: name,
            isBoot: true,
            isReadOnly: false,
            totalCapacity: total,
            availableCapacity: available
        )
    }

    /// Returns true for volumes MacSift must never offer the user. Includes
    /// macOS system mounts (Recovery, VM, Preboot, Update) and Time Machine
    /// backup disks — deleting from those would be catastrophic.
    private static func isBlocked(url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let lastComponent = url.lastPathComponent.lowercased()
        let blockedLastComponents: Set<String> = [
            "recovery", "preboot", "update", "vm", "xarts", "iscpreboot", "hardware",
        ]
        if blockedLastComponents.contains(lastComponent) { return true }

        // Time Machine backup disks expose `Backups.backupdb` at the root.
        let fm = FileManager.default
        if fm.fileExists(atPath: url.appending(path: "Backups.backupdb").path(percentEncoded: false)) {
            return true
        }
        if fm.fileExists(atPath: url.appending(path: ".com.apple.TMCheckpoint").path(percentEncoded: false)) {
            return true
        }

        // The volume literally named "Time Machine"
        if lastComponent.contains("time machine") { return true }

        // System volumes typically live under /System/Volumes/* — we don't
        // want to touch anything there.
        if path.hasPrefix("/System/Volumes/") { return true }

        return false
    }
}
