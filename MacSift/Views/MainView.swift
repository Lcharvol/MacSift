import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exclusionManager: ExclusionManager
    @EnvironmentObject var updateVM: UpdateViewModel
    @StateObject private var scanVM: ScanViewModel
    @StateObject private var cleaningVM: CleaningViewModel
    // Per-window UI state. SceneStorage persists these across app launches so
    // re-opening the window restores the user's last view preferences.
    @SceneStorage("MainView.selectedCategoryRaw") private var selectedCategoryRaw: String = ""
    @SceneStorage("MainView.selectedVolumeID") private var selectedVolumeIDRaw: String = ""
    @SceneStorage("MainView.showAllFiles") private var showAllFiles = false
    @SceneStorage("MainView.sortOptionRaw") private var sortOptionRaw: String = FileListSortOption.sizeDesc.rawValue
    // Inspector state is intentionally NOT persisted — without an inspectedGroup
    // (which is in-memory only), an open inspector after relaunch would just
    // show the empty placeholder, which is confusing.
    @State private var isInspectorPresented = false
    @State private var searchQuery: String = ""
    @State private var inspectedGroup: FileGroup?
    /// When non-nil, the file list shows every ScannedFile in this group
    /// instead of the grouped view. Acts as a "drill down" for power users.
    @State private var expandedGroup: FileGroup?
    /// Cached multi-selection summary. Recomputed ONLY when selectedIDs or
    /// allSortedGroups change — never on every MainView body re-render.
    /// Without this cache, every keystroke in the search field triggered
    /// an O(all files) iteration inside the inspector closure, which on
    /// big scans (50k+ files) produced visible freezes.
    @State private var cachedSelectionSummary: SelectionSummary = SelectionSummary(
        groupCount: 0, fileCount: 0, totalSize: 0, countByCategory: [:]
    )
    /// Tracks the currently-running freed-banner dismissal task so rapid
    /// repeated cleanings don't pile up sleeping tasks in memory.
    @State private var bannerDismissTask: Task<Void, Never>?
    /// Size of the most recent cleaning report — used to show a "freed X GB"
    /// banner after the auto-rescan finishes.
    @State private var pendingFreedSize: Int64 = 0
    /// The visible banner message. When non-nil, shown above the results.
    @State private var freedBanner: String?
    /// Cached volume-filtered views. Recomputed ONLY when the scan
    /// finishes or the user switches volumes — NOT on every category
    /// click. Without this cache, clicking a category re-walked every
    /// file in `filteringVolume`, every group in `filteredGroupsByCategory`,
    /// and every file again in `sizeByVolume` — O(n) work on the render
    /// thread × 4 per click, which at 100k+ files produced visible freezes.
    @State private var cachedDisplayedResult: ScanResult = .empty
    @State private var cachedSizeByVolume: [String: Int64] = [:]
    @State private var cachedFilteredGroupsByCategory: [FileCategory: [FileGroup]] = [:]
    @State private var cachedFilteredAllSortedGroups: [FileGroup] = []
    /// When true, the detail view shows `DuplicatesListView` instead
    /// of the regular category/file list. Flipped by the sidebar row
    /// so the user can bounce back and forth without losing their
    /// search query or category selection.
    @State private var showDuplicates = false

    private var selectedCategory: FileCategory? {
        FileCategory(rawValue: selectedCategoryRaw)
    }

    private var selectedCategoryBinding: Binding<FileCategory?> {
        Binding(
            get: { FileCategory(rawValue: selectedCategoryRaw) },
            set: { selectedCategoryRaw = $0?.rawValue ?? "" }
        )
    }

    private var selectedVolumeID: String? {
        selectedVolumeIDRaw.isEmpty ? nil : selectedVolumeIDRaw
    }

    private var selectedVolumeIDBinding: Binding<String?> {
        Binding(
            get: { selectedVolumeIDRaw.isEmpty ? nil : selectedVolumeIDRaw },
            set: { selectedVolumeIDRaw = $0 ?? "" }
        )
    }

    /// Read from the caches populated by `refreshVolumeCaches`. NEVER walk
    /// files or groups from inside a computed property — that work must
    /// happen off the render path.
    private var displayedResult: ScanResult { cachedDisplayedResult }
    private var sizeByVolume: [String: Int64] { cachedSizeByVolume }

    private var sortOption: FileListSortOption {
        FileListSortOption(rawValue: sortOptionRaw) ?? .sizeDesc
    }

    init(exclusionManager: ExclusionManager, appState: AppState) {
        _scanVM = StateObject(wrappedValue: ScanViewModel(exclusionManager: exclusionManager, appState: appState))
        _cleaningVM = StateObject(wrappedValue: CleaningViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            UpdateBannerView(updateVM: updateVM)
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } detail: {
                detailContent
                    .background(.background)
            }
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
            if newState.isScanning {
                // Clear the cached filtered views so the sidebar doesn't
                // keep showing the previous scan's totals while a fresh
                // scan is in progress. Without this the VolumePicker and
                // CategoryList displayed stale sizes for the full duration
                // of the new scan.
                cachedDisplayedResult = .empty
                cachedSizeByVolume = [:]
                cachedFilteredGroupsByCategory = [:]
                cachedFilteredAllSortedGroups = []
                showDuplicates = false
            }
            if newState.isCompleted {
                cleaningVM.updateFileIndex(from: scanVM.result)
                refreshSelectionSummary()
                // Drop the volume filter if the selected volume isn't in
                // the fresh result (e.g., it was unplugged between scans).
                if let current = selectedVolumeID,
                   !scanVM.scannedVolumes.contains(where: { $0.id == current })
                {
                    selectedVolumeIDRaw = ""
                }
                // Rebuild volume-scoped caches off the main thread — never
                // walk 100k+ files from inside a computed property.
                refreshVolumeCaches()

                // Post-cleanup banner: show "You freed X" for a few seconds
                // after an auto-rescan triggered by a real cleanup.
                if pendingFreedSize > 0 {
                    freedBanner = "You just freed \(pendingFreedSize.formattedFileSize)."
                    pendingFreedSize = 0
                    scheduleBannerDismissal()
                }
            }
        }
        .onChange(of: cleaningVM.selectionVersion) { _, _ in
            // Observe the int counter instead of the Set itself — equality
            // on a Set<String> with thousands of entries is O(n) per render.
            refreshSelectionSummary()
        }
        .onChange(of: cleaningVM.state) { _, newState in
            // Auto-rescan after a successful real (non-dry-run) cleaning so
            // the displayed sizes reflect the new state on disk.
            if newState == .completed,
               appState.isDryRun == false,
               let report = cleaningVM.report,
               report.deletedCount > 0
            {
                // Remember the freed size so we can show a banner after the
                // next scan completes.
                pendingFreedSize = report.freedSize
                scanVM.startScan()
            }
        }
        .onChange(of: selectedCategoryRaw) { _, newValue in
            showAllFiles = false      // reset cap when switching categories
            searchQuery = ""          // clear filter so the new category shows everything
            inspectedGroup = nil      // clear stale inspector content
            expandedGroup = nil       // collapse any drill-down
            if !newValue.isEmpty {
                // User explicitly clicked a category — leave the
                // duplicates view if we were in it.
                showDuplicates = false
            }
        }
        .onChange(of: selectedVolumeIDRaw) { _, _ in
            // Volume switch is rare and heavy — fan out to a detached Task.
            refreshVolumeCaches()
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
            cleaningVM.setSelectedIDs([])
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            // Volume picker only appears once a scan has discovered more
            // than one volume — single-volume users get the clean original UI.
            if scanVM.scannedVolumes.count > 1 {
                VolumePickerView(
                    volumes: scanVM.scannedVolumes,
                    sizeByVolume: sizeByVolume,
                    selectedVolumeID: selectedVolumeIDBinding
                )
                Divider().opacity(0.5)
            }

            // Duplicates entry surfaces only when the finder caught
            // at least one set — no point wasting sidebar space with
            // an empty row on a deduped machine.
            if !scanVM.duplicateSets.isEmpty {
                duplicatesRow
                Divider().opacity(0.5)
            }

            CategoryListView(
                sizeByCategory: displayedResult.sizeByCategory,
                countByCategory: displayedResult.countByCategory,
                selectedCategory: selectedCategoryBinding
            )
            .scrollContentBackground(.hidden)
        }
    }

    private var duplicatesRow: some View {
        Button {
            showDuplicates = true
            selectedCategoryRaw = ""  // clear category selection when entering dupes view
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.callout)
                    .foregroundStyle(showDuplicates ? Color.white : Color.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Duplicates")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(showDuplicates ? .white : .primary)
                    Text("\(scanVM.duplicateSets.count) sets · \(totalDuplicateWaste.formattedFileSize) reclaimable")
                        .font(.caption2)
                        .foregroundStyle(showDuplicates ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(showDuplicates ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var totalDuplicateWaste: Int64 {
        scanVM.state.completedScan?.totalDuplicateWaste ?? 0
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
        if scanVM.state.isCancelling { return String(localized: "Cancelling…") }
        if scanVM.state.isScanning { return String(localized: "Cancel Scan") }
        return String(localized: "Start Scan")
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
            if let freedBanner {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(freedBanner)
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button {
                        withAnimation { self.freedBanner = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.green.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            resultsHeader

            StorageBarView(
                result: displayedResult,
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
                Menu {
                    Picker("Sort by", selection: Binding(
                        get: { sortOption },
                        set: { sortOptionRaw = $0.rawValue }
                    )) {
                        ForEach(FileListSortOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort file list")
            }
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
            InspectorView(
                group: inspectedGroup,
                selectionSummary: inspectedGroup == nil ? cachedSelectionSummary : nil,
                onExclude: { url in exclusionManager.addExclusion(url) },
                onExpand: { group in expandedGroup = group }
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    /// Recompute the multi-selection summary. Called from onChange handlers
    /// that fire ONLY when the selection or the scan result changes —
    /// not on every view body re-render.
    private func refreshSelectionSummary() {
        cachedSelectionSummary = cleaningVM.selectionSummary(using: scanVM.allSortedGroups)
    }

    /// Dismiss the freed banner after 5 seconds. Cancels any previous
    /// pending dismissal so rapid clean+rescan cycles don't pile up sleeping
    /// tasks — each call replaces the timer.
    private func scheduleBannerDismissal() {
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            withAnimation { freedBanner = nil }
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
                    .help(inaccessibleHelpText)
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
        if showDuplicates {
            DuplicatesListView(
                sets: scanVM.duplicateSets,
                selectedIDs: cleaningVM.selectedIDs,
                onToggleFile: { [weak cleaningVM] file in cleaningVM?.toggleFile(file) },
                onKeepOldest: { [weak cleaningVM] set in
                    cleaningVM?.keepOldestInDuplicateSet(set)
                }
            )
        } else if let expanded = expandedGroup {
            ExpandedGroupView(
                group: expanded,
                selectedIDs: cleaningVM.selectedIDs,
                onToggleFile: { [weak cleaningVM] file in cleaningVM?.toggleFile(file) },
                onClose: { expandedGroup = nil }
            )
        } else {
            FileListSection(
                groupsByCategory: filteredGroupsByCategory,
                allSortedGroups: filteredAllSortedGroups,
                selectedCategory: selectedCategory,
                searchQuery: searchQuery,
                isAdvanced: appState.mode == .advanced,
                sortOption: sortOption,
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
    }

    private var filteredGroupsByCategory: [FileCategory: [FileGroup]] {
        cachedFilteredGroupsByCategory
    }
    private var filteredAllSortedGroups: [FileGroup] {
        cachedFilteredAllSortedGroups
    }

    /// Recompute every volume-scoped cached view. Called ONLY when the
    /// scan finishes or the selected volume changes. Heavy work (iterating
    /// every scanned file) is dispatched to a detached Task so we never
    /// block the main thread, and the result is assigned in a single
    /// @State write to avoid a cascade of SwiftUI invalidations.
    private func refreshVolumeCaches() {
        let fullResult = scanVM.result
        let groupsByCategory = scanVM.groupsByCategory
        let allSortedGroups = scanVM.allSortedGroups
        let volumeID = selectedVolumeID

        Task.detached(priority: .userInitiated) {
            // `filteringVolume` walks files once and is O(n) in the
            // filtered subset. The size-by-volume map walks every file
            // in the full result ONCE, independent of which volume is
            // currently selected — so the picker always has truthful
            // totals even while a filter is applied.
            let filteredResult = fullResult.filteringVolume(volumeID)

            var sizeByVolume: [String: Int64] = [:]
            for files in fullResult.filesByCategory.values {
                for file in files {
                    sizeByVolume[file.volumeID, default: 0] += file.size
                }
            }

            // Group filtering: when no volume is selected, pass through
            // the VM's already-sorted views untouched (O(1)).
            let filteredGroupsByCategory: [FileCategory: [FileGroup]]
            let filteredAllSortedGroups: [FileGroup]
            if let volumeID {
                filteredGroupsByCategory = groupsByCategory.mapValues { groups in
                    groups.filter { group in group.files.contains { $0.volumeID == volumeID } }
                }
                filteredAllSortedGroups = allSortedGroups.filter { group in
                    group.files.contains { $0.volumeID == volumeID }
                }
            } else {
                filteredGroupsByCategory = groupsByCategory
                filteredAllSortedGroups = allSortedGroups
            }

            await MainActor.run {
                self.cachedDisplayedResult = filteredResult
                self.cachedSizeByVolume = sizeByVolume
                self.cachedFilteredGroupsByCategory = filteredGroupsByCategory
                self.cachedFilteredAllSortedGroups = filteredAllSortedGroups
            }
        }
    }

    private var headerSubtitle: String {
        let activeResult = displayedResult
        let count = activeResult.totalFileCount
        let size = activeResult.totalSize.formattedFileSize
        let duration = scanVM.result.scanDuration
        var parts = ["\(count) files", size]
        if let volumeID = selectedVolumeID,
           let volume = scanVM.scannedVolumes.first(where: { $0.id == volumeID })
        {
            parts.insert("on \(volume.name)", at: 0)
        }
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

    /// Hover text listing up to 10 unreadable paths — gives the user a hint
    /// about which folders need Full Disk Access. Empty string means no
    /// tooltip (hover is a no-op).
    private var inaccessibleHelpText: String {
        let paths = scanVM.result.inaccessiblePaths
        guard !paths.isEmpty else { return "" }
        let preview = paths.prefix(10).joined(separator: "\n")
        let extra = paths.count > 10 ? "\n…and \(paths.count - 10) more" : ""
        return "Inaccessible paths (sample):\n\(preview)\(extra)"
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
