import Testing
import Foundation
@testable import MacSift

@Suite("Volume Discovery")
struct VolumeDiscoveryTests {
    @Test func bootVolumeIsAlwaysFirst() {
        let volumes = VolumeDiscovery.list()
        // In any test environment there should be at least the boot volume.
        // If discovery returned something, the first entry must be the boot.
        #expect(!volumes.isEmpty)
        #expect(volumes.first?.isBoot == true)
    }

    @Test func discoveredVolumesHaveStablePathIDs() {
        let volumes = VolumeDiscovery.list()
        for volume in volumes {
            // The id is the volume's resolved path — never empty, always
            // starts with "/".
            #expect(!volume.id.isEmpty)
            #expect(volume.id.hasPrefix("/"))
        }
    }

    @Test func discoveredVolumesHaveUniqueIDs() {
        let volumes = VolumeDiscovery.list()
        let ids = volumes.map(\.id)
        #expect(ids.count == Set(ids).count, "Duplicate volume IDs in discovery output")
    }
}

@Suite("ScannedFile volume stamping")
struct ScannedFileVolumeTests {
    @Test func defaultVolumeIDIsBootSentinel() {
        let file = ScannedFile(
            url: URL(filePath: "/tmp/test.bin"),
            size: 100,
            category: .tempFiles,
            description: "",
            modificationDate: .now,
            isDirectory: false
        )
        #expect(file.volumeID == Volume.bootVolumeID)
    }

    @Test func explicitVolumeIDIsPreserved() {
        let file = ScannedFile(
            url: URL(filePath: "/Volumes/T7/movie.mov"),
            size: 100,
            category: .largeFiles,
            description: "",
            modificationDate: .now,
            isDirectory: false,
            volumeID: "/Volumes/T7"
        )
        #expect(file.volumeID == "/Volumes/T7")
    }

    @Test func filteringVolumeReturnsOnlyMatchingFiles() {
        let boot = ScannedFile(
            url: URL(filePath: "/Users/x/a.log"),
            size: 1,
            category: .logs,
            description: "",
            modificationDate: .now,
            isDirectory: false,
            volumeID: "/"
        )
        let external = ScannedFile(
            url: URL(filePath: "/Volumes/T7/movie.mov"),
            size: 2,
            category: .largeFiles,
            description: "",
            modificationDate: .now,
            isDirectory: false,
            volumeID: "/Volumes/T7"
        )
        let result = ScanResult(
            filesByCategory: [.logs: [boot], .largeFiles: [external]],
            scanDuration: 0
        )

        let bootOnly = result.filteringVolume("/")
        #expect(bootOnly.totalFileCount == 1)
        #expect(bootOnly.filesByCategory[.logs]?.first?.id == boot.id)
        #expect(bootOnly.filesByCategory[.largeFiles] == nil)

        let externalOnly = result.filteringVolume("/Volumes/T7")
        #expect(externalOnly.totalFileCount == 1)
        #expect(externalOnly.filesByCategory[.largeFiles]?.first?.id == external.id)

        let all = result.filteringVolume(nil)
        #expect(all.totalFileCount == 2)
    }
}
