import Testing
import Foundation
@testable import MacSift

@MainActor
@Suite("CleaningViewModel")
struct CleaningViewModelTests {
    private func makeFile(_ name: String, size: Int64) -> ScannedFile {
        ScannedFile(
            url: URL(filePath: "/tmp/group-test-\(name)"),
            size: size,
            category: .cache,
            description: "test",
            modificationDate: .now,
            isDirectory: false
        )
    }

    private func makeGroup(files: [ScannedFile]) -> FileGroup {
        FileGroup(
            id: "test-group-\(UUID().uuidString)",
            label: "Test group",
            category: .cache,
            totalSize: files.reduce(0) { $0 + $1.size },
            fileCount: files.count,
            files: files,
            topFiles: files,
            mostRecentModificationDate: .now,
            representativeURL: URL(filePath: "/tmp/group-test")
        )
    }

    private func makeVM(with files: [ScannedFile]) -> CleaningViewModel {
        let appState = AppState()
        let vm = CleaningViewModel(appState: appState)
        var dict: [FileCategory: [ScannedFile]] = [:]
        for file in files {
            dict[file.category, default: []].append(file)
        }
        let result = ScanResult(filesByCategory: dict, scanDuration: 0)
        vm.updateFileIndex(from: result)
        // updateFileIndex runs asynchronously — give it a moment to settle.
        // In production we'd wait on the internal Task, but for tests we can
        // just call it and then directly set the index via the public API.
        return vm
    }

    @Test func toggleGroupSelectsAllFilesWhenNoneSelected() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Directly seed selectedIDs via toggleGroup (no prior selection)
        vm.toggleGroup(group)

        #expect(vm.selectedIDs.count == 3)
        #expect(vm.selectedIDs.isSuperset(of: Set(files.map(\.id))))
    }

    @Test func toggleGroupDeselectsAllFilesWhenAllSelected() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Pre-select all
        vm.setSelectedIDs(Set(files.map(\.id)))

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.isEmpty)
    }

    @Test func toggleGroupOnPartiallySelectedSelectsAll() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Select only one
        vm.setSelectedIDs([files[0].id])

        vm.toggleGroup(group)

        // Partial → full
        #expect(vm.selectedIDs.count == 3)
    }

    @Test func keepOldestInDuplicateSetSelectsAllButTheOldest() async {
        let now = Date()
        let olderDate = now.addingTimeInterval(-86_400 * 30)  // 30 days ago
        let newestDate = now.addingTimeInterval(-3_600)        // 1 hour ago

        let oldest = ScannedFile(
            url: URL(filePath: "/tmp/original.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: olderDate,
            isDirectory: false
        )
        let middle = ScannedFile(
            url: URL(filePath: "/tmp/copy-a.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: now.addingTimeInterval(-86_400),
            isDirectory: false
        )
        let newest = ScannedFile(
            url: URL(filePath: "/tmp/copy-b.bin"),
            size: 2_000_000,
            category: .largeFiles,
            description: "",
            modificationDate: newestDate,
            isDirectory: false
        )
        let set = DuplicateSet(id: "hash", size: 2_000_000, files: [middle, newest, oldest])

        let vm = makeVM(with: [oldest, middle, newest])
        await Task.yield()
        await Task.yield()
        vm.keepOldestInDuplicateSet(set)

        // The oldest is NOT in the selection; both newer copies ARE.
        #expect(!vm.selectedIDs.contains(oldest.id))
        #expect(vm.selectedIDs.contains(middle.id))
        #expect(vm.selectedIDs.contains(newest.id))
        #expect(vm.selectedIDs.count == 2)
    }

    @Test func toggleGroupDoesNotAffectUnrelatedSelection() async {
        let groupFiles = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let otherFile = makeFile("other", size: 500)
        let group = makeGroup(files: groupFiles)

        let vm = makeVM(with: groupFiles + [otherFile])
        vm.setSelectedIDs([otherFile.id])

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.contains(otherFile.id))
        #expect(vm.selectedIDs.count == 3)  // otherFile + both group files
    }
}
