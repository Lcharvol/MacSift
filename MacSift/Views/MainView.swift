import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scanVM: ScanViewModel
    @StateObject private var cleaningVM: CleaningViewModel
    // Per-window UI state. SceneStorage persists these across app launches so
    // re-opening the window restores the user's last view preferences.
    @SceneStorage("MainView.selectedCategoryRaw") private var selectedCategoryRaw: String = ""
    @SceneStorage("MainView.showAllFiles") private var showAllFiles = false
    // Inspector state is intentionally NOT persisted — without an inspectedGroup
    // (which is in-memory only), an open inspector after relaunch would just
    // show the empty placeholder, which is confusing.
    @State private var isInspectorPresented = false
    @State private var searchQuery: String = ""
    @State private var inspectedGroup: FileGroup?

    private var selectedCategory: FileCategory? {
        FileCategory(rawValue: selectedCategoryRaw)
    }

    private var selectedCategoryBinding: Binding<FileCategory?> {
        Binding(
            get: { FileCategory(rawValue: selectedCategoryRaw) },
            set: { selectedCategoryRaw = $0?.rawValue ?? "" }
        )
    }

    init(exclusionManager: ExclusionManager, appState: AppState) {
        _scanVM = StateObject(wrappedValue: ScanViewModel(exclusionManager: exclusionManager, appState: appState))
        _cleaningVM = StateObject(wrappedValue: CleaningViewModel(appState: appState))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            detailContent
                .background(.background)
        }
        // Drop a folder anywhere on the window to scan JUST that folder.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.hasDirectoryPath else { return }
                Task { @MainActor in
                    scanVM.startScan(folder: url)
                }
            }
            return true
        }
        .sheet(isPresented: $cleaningVM.showPreview) {
            CleaningPreviewView(cleaningVM: cleaningVM, appState: appState)
        }
        .onChange(of: scanVM.state) { _, newState in
            if newState.isCompleted {
                cleaningVM.updateFileIndex(from: scanVM.result)
            }
        }
        .onChange(of: cleaningVM.state) { _, newState in
            // Auto-rescan after a successful real (non-dry-run) cleaning so
            // the displayed sizes reflect the new state on disk.
            if newState == .completed,
               appState.isDryRun == false,
               (cleaningVM.report?.deletedCount ?? 0) > 0
            {
                scanVM.startScan()
            }
        }
        .onChange(of: selectedCategoryRaw) { _, _ in
            showAllFiles = false      // reset cap when switching categories
            searchQuery = ""          // clear filter so the new category shows everything
            inspectedGroup = nil      // clear stale inspector content
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSiftStartScan)) { _ in
            scanVM.startScan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSiftCancelScan)) { _ in
            scanVM.cancelScan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSiftSelectAllSafe)) { _ in
            cleaningVM.selectAllSafe(from: scanVM.result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macSiftDeselectAll)) { _ in
            cleaningVM.selectedIDs.removeAll()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            CategoryListView(
                sizeByCategory: scanVM.result.sizeByCategory,
                countByCategory: scanVM.result.countByCategory,
                selectedCategory: selectedCategoryBinding
            )
            .scrollContentBackground(.hidden)
        }
    }

    private var sidebarHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("MacSift")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Button {
                if scanVM.state.isScanning {
                    scanVM.cancelScan()
                } else if !scanVM.state.isCancelling {
                    scanVM.startScan()
                }
            } label: {
                Label(scanButtonLabel, systemImage: scanButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(scanVM.state.isCancelling)
        }
        .padding(16)
    }

    private var scanButtonLabel: String {
        if scanVM.state.isCancelling { return "Cancelling…" }
        if scanVM.state.isScanning { return "Cancel Scan" }
        return "Start Scan"
    }

    private var scanButtonIcon: String {
        if scanVM.state.isCancelling { return "hourglass" }
        if scanVM.state.isScanning { return "stop.circle" }
        return "magnifyingglass"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch scanVM.state {
        case .idle:
            WelcomeView(
                hasFullDiskAccess: scanVM.hasFullDiskAccess,
                onStartScan: { scanVM.startScan() },
                onOpenFullDiskAccess: { FullDiskAccess.openSystemSettings() }
            )
        case .scanning, .cancelling:
            ScanProgressView(progress: scanVM.displayProgress)
        case .completed:
            resultsView
        }
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader

            StorageBarView(
                result: scanVM.result,
                selectedCategory: selectedCategoryBinding
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.5)

            fileListView

            bottomBar
        }
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Filter by name")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    scanVM.startScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Rescan disk (⌘R)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Toggle inspector")
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(group: inspectedGroup)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory?.label ?? "All Categories")
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedCategory != nil {
                Button {
                    selectedCategoryRaw = ""
                } label: {
                    Label("Clear filter", systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var fileListView: some View {
        FileListSection(
            groupsByCategory: scanVM.groupsByCategory,
            allSortedGroups: scanVM.allSortedGroups,
            selectedCategory: selectedCategory,
            searchQuery: searchQuery,
            isAdvanced: appState.mode == .advanced,
            selectedIDs: cleaningVM.selectedIDs,
            inspectedGroupID: inspectedGroup?.id,
            showAllFiles: $showAllFiles,
            onToggleGroup: { [weak cleaningVM] group in cleaningVM?.toggleGroup(group) },
            onInspectGroup: { group in
                inspectedGroup = group
                isInspectorPresented = true
            }
        )
    }

    private var headerSubtitle: String {
        let count = scanVM.result.totalFileCount
        let size = scanVM.result.totalSize.formattedFileSize
        let duration = scanVM.result.scanDuration
        var parts = ["\(count) files", size]
        if duration > 0 {
            parts.append("scanned in \(String(format: "%.1fs", duration))")
        }
        if let completedAt = scanVM.state.completedScan?.completedAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append(formatter.localizedString(for: completedAt, relativeTo: Date()))
        }
        let inaccessible = scanVM.result.inaccessibleCount
        if inaccessible > 0 {
            parts.append("\(inaccessible) inaccessible")
        }
        return parts.joined(separator: " · ")
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if cleaningVM.selectedCount > 0 {
                Text("^[\(cleaningVM.selectedCount) file](inflect: true) · \(cleaningVM.selectedSize.formattedFileSize)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Tick rows to select what to clean")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let category = selectedCategory,
               let files = scanVM.sortedFilesByCategory[category],
               !files.isEmpty
            {
                Button {
                    cleaningVM.selectAllInCategory(category, files: files)
                } label: {
                    Label("Select all in \(category.label)", systemImage: "checkmark.circle")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else if appState.mode == .simple {
                Button {
                    cleaningVM.selectAllSafe(from: scanVM.result)
                } label: {
                    Label("Select all safe", systemImage: "checkmark.shield")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Button {
                cleaningVM.showCleaningPreview()
            } label: {
                Label("Clean Selected", systemImage: "trash")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(cleaningVM.selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
    }
}
