import Testing
import Foundation
@testable import MacSift

@MainActor
@Suite("ExclusionManager")
struct ExclusionManagerTests {
    @Test func startsEmpty() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        #expect(manager.excludedPaths.isEmpty)
    }

    @Test func addsExclusion() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        #expect(manager.excludedPaths.count == 1)
        #expect(manager.isExcluded(url))
    }

    @Test func removesExclusion() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        manager.removeExclusion(url)
        #expect(manager.excludedPaths.isEmpty)
        #expect(!manager.isExcluded(url))
    }

    @Test func excludesChildPaths() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let parent = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(parent)
        let child = URL(filePath: "/Users/test/Documents/keep/subdir/file.txt")
        #expect(manager.isExcluded(child))
    }

    @Test func doesNotExcludeUnrelatedPaths() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        let other = URL(filePath: "/Users/test/Downloads/file.txt")
        #expect(!manager.isExcluded(other))
    }

    @Test func persistsExclusions() {
        let suite = "test.\(UUID().uuidString)"
        let url = URL(filePath: "/Users/test/Documents/keep")

        let manager1 = ExclusionManager(userDefaultsSuiteName: suite)
        manager1.addExclusion(url)

        let manager2 = ExclusionManager(userDefaultsSuiteName: suite)
        #expect(manager2.isExcluded(url))
    }
}
