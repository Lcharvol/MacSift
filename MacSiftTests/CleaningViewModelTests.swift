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
        vm.selectedIDs = Set(files.map(\.id))

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.isEmpty)
    }

    @Test func toggleGroupOnPartiallySelectedSelectsAll() async {
        let files = [makeFile("a", size: 100), makeFile("b", size: 200), makeFile("c", size: 300)]
        let group = makeGroup(files: files)

        let vm = makeVM(with: files)
        // Select only one
        vm.selectedIDs = [files[0].id]

        vm.toggleGroup(group)

        // Partial → full
        #expect(vm.selectedIDs.count == 3)
    }

    @Test func toggleGroupDoesNotAffectUnrelatedSelection() async {
        let groupFiles = [makeFile("a", size: 100), makeFile("b", size: 200)]
        let otherFile = makeFile("other", size: 500)
        let group = makeGroup(files: groupFiles)

        let vm = makeVM(with: groupFiles + [otherFile])
        vm.selectedIDs = [otherFile.id]

        vm.toggleGroup(group)

        #expect(vm.selectedIDs.contains(otherFile.id))
        #expect(vm.selectedIDs.count == 3)  // otherFile + both group files
    }
}
