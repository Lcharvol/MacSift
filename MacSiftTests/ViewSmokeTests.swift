import Testing
import Foundation
import SwiftUI
@testable import MacSift

/// Smoke tests for the standalone views. These don't render anything — the
/// goal is to catch signature drift and crashes in view initializers, plus
/// force-evaluate `body` once so obvious issues (unwrapped nils, malformed
/// state) surface at test time instead of at runtime.
@MainActor
@Suite("View Smoke")
struct ViewSmokeTests {
    private func makeFile(_ name: String, size: Int64, category: FileCategory = .largeFiles) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/view-smoke-\(name)"),
            size: size,
            category: category,
            description: "smoke",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeGroup(label: String, files: [ScannedFile]) -> FileGroup {
        FileGroup(
            id: "smoke-\(label)",
            label: label,
            category: files.first?.category ?? .largeFiles,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files,
            topFiles: files,
            mostRecentModificationDate: .now,
            representativeURL: URL(filePath: "/tmp/view-smoke-\(label)")
        )
    }

    @Test func welcomeViewInstantiates() {
        let view = WelcomeView(
            hasFullDiskAccess: false,
            onStartScan: {},
            onOpenFullDiskAccess: {}
        )
        _ = view.body
    }

    @Test func welcomeViewWithAccessInstantiates() {
        let view = WelcomeView(
            hasFullDiskAccess: true,
            onStartScan: {},
            onOpenFullDiskAccess: {}
        )
        _ = view.body
    }

    @Test func scanProgressViewInstantiates() {
        let progress = ScanDisplayProgress(
            totalFiles: 1_234,
            totalSize: 5 * 1024 * 1024 * 1024,
            currentPath: "/tmp/view-smoke-current",
            currentCategory: .cache,
            sizeByCategory: [.cache: 2_000_000, .logs: 500_000]
        )
        let view = ScanProgressView(progress: progress)
        _ = view.body
    }

    @Test func scanProgressViewWithEmptyStateInstantiates() {
        let view = ScanProgressView(progress: ScanDisplayProgress())
        _ = view.body
    }

    @Test func storageBarViewInstantiates() {
        let result = ScanResult(
            filesByCategory: [
                .cache: [makeFile("a", size: 100_000, category: .cache)],
                .logs: [makeFile("b", size: 200_000, category: .logs)],
                .largeFiles: [makeFile("c", size: 1_000_000_000, category: .largeFiles)],
            ],
            scanDuration: 2.4
        )
        var selected: FileCategory? = nil
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let view = StorageBarView(result: result, selectedCategory: binding)
        _ = view.body
    }

    @Test func storageBarViewWithEmptyResultInstantiates() {
        var selected: FileCategory? = nil
        let binding = Binding(get: { selected }, set: { selected = $0 })
        let view = StorageBarView(result: .empty, selectedCategory: binding)
        _ = view.body
    }

    @Test func expandedGroupViewInstantiates() {
        let files = (0..<5).map { makeFile("e\($0)", size: Int64(($0 + 1) * 1_000_000)) }
        let group = makeGroup(label: "Expanded", files: files)
        let view = ExpandedGroupView(
            group: group,
            selectedIDs: [files[0].id, files[2].id],
            onToggleFile: { _ in },
            onClose: {}
        )
        _ = view.body
    }

    @Test func expandedGroupViewWithSingletonInstantiates() {
        let files = [makeFile("solo", size: 500_000_000)]
        let group = makeGroup(label: "Solo", files: files)
        let view = ExpandedGroupView(
            group: group,
            selectedIDs: [],
            onToggleFile: { _ in },
            onClose: {}
        )
        _ = view.body
    }
}
