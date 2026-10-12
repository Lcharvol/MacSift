import Testing
import Foundation
@testable import MacSift

/// `ScanMode.demo` exists so documentation screenshots can be taken against
/// disposable fixture data. Its defining property is containment: every root
/// it scans must resolve inside the directory it was handed, so a demo run
/// can never read the real home directory.
@Suite("Demo mode")
struct DemoModeTests {
    /// Builds a miniature home: a cache bundle, a log, a temp file and a
    /// large file, mirroring the categories a real scan would surface.
    private func makeDemoRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "MacSiftDemo-\(UUID().uuidString)")
        let fm = FileManager.default

        let cache = root.appending(path: "Library/Caches/com.demo.app")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 4096).write(to: cache.appending(path: "cache.db"))

        let logs = root.appending(path: "Library/Logs")
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 2048).write(to: logs.appending(path: "demo.log"))

        let tmp = root.appending(path: "tmp")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try Data(repeating: 0xCC, count: 1024).write(to: tmp.appending(path: "scratch.tmp"))

        return root
    }

    private func makeScanner(root: URL) async -> DiskScanner {
        let exclusionManager = await MainActor.run {
            ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        }
        return DiskScanner(
            classifier: CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024),
            exclusionManager: exclusionManager,
            homeDirectory: root,
            mode: .demo
        )
    }

    @Test("every scanned file stays inside the demo root")
    func demoScanIsContained() async throws {
        let root = try makeDemoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await makeScanner(root: root).scan()

        // The containment guarantee — the whole reason this mode exists.
        let rootPath = root.standardizedFileURL.path
        for file in result.filesByCategory.values.flatMap({ $0 }) {
            #expect(
                file.url.standardizedFileURL.path.hasPrefix(rootPath),
                "demo scan escaped its root: \(file.url.path)"
            )
        }
    }

    @Test("demo mode finds the fixture data it was pointed at")
    func demoScanFindsFixtures() async throws {
        let root = try makeDemoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await makeScanner(root: root).scan()

        #expect(!result.filesByCategory.values.flatMap({ $0 }).isEmpty, "demo scan found nothing to show")
        #expect(result.filesByCategory[.cache, default: []].contains { $0.url.lastPathComponent == "cache.db" })
        #expect(result.filesByCategory[.logs, default: []].contains { $0.url.lastPathComponent == "demo.log" })
    }

    /// `.boot` reads `/tmp` and `/private/var/log` via absolute paths. `.demo`
    /// deliberately omits both, since they sit outside any sandbox root.
    @Test("demo mode never reaches the absolute system roots")
    func demoScanSkipsAbsoluteRoots() async throws {
        let root = try makeDemoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = await makeScanner(root: root).scan()

        for file in result.filesByCategory.values.flatMap({ $0 }) {
            let path = file.url.standardizedFileURL.path
            #expect(!path.hasPrefix("/private/var/log"))
            // The fixture's own tmp lives under the root, so only reject the
            // system one.
            #expect(!path.hasPrefix("/tmp/") || path.hasPrefix(root.standardizedFileURL.path))
        }
    }
}
