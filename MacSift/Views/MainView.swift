import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scanVM: ScanViewModel
    @StateObject private var cleaningVM: CleaningViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showAllFiles = false
    @State private var searchQuery: String = ""

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
        .sheet(isPresented: $cleaningVM.showPreview) {
            CleaningPreviewView(cleaningVM: cleaningVM, appState: appState)
        }
        .onChange(of: scanVM.state) { _, newState in
            if newState.isCompleted {
                cleaningVM.updateFileIndex(from: scanVM.result)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            showAllFiles = false  // reset cap when switching categories
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
                selectedCategory: $selectedCategory
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
                } else {
                    scanVM.startScan()
                }
            } label: {
                Label(
                    scanVM.state.isScanning ? "Cancel Scan" : "Start Scan",
                    systemImage: scanVM.state.isScanning ? "stop.circle" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(16)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch scanVM.state {
        case .idle:
            welcomeView
        case .scanning:
            ScanProgressView(progress: scanVM.displayProgress)
        case .completed:
            resultsView
        }
    }


    private var welcomeView: some View {
        VStack(spacing: 28) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .padding(28)
                .glassEffect(.regular, in: Circle())

            VStack(spacing: 6) {
                Text("Welcome to MacSift")
                    .font(.largeTitle.weight(.semibold))
                Text("Discover what's taking up space, with full transparency.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !scanVM.hasFullDiskAccess {
                fullDiskAccessBanner
                    .padding(.top, 4)
            }

            Button {
                scanVM.startScan()
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Full Disk Access Required")
                    .font(.callout.weight(.medium))
                Text("Some system files won't be scanned without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 480)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader

            StorageBarView(
                result: scanVM.result,
                selectedCategory: $selectedCategory
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
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory?.label ?? "All Categories")
                    .font(.title2.weight(.semibold))
                Text("\(scanVM.result.totalFileCount) files · \(scanVM.result.totalSize.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedCategory != nil {
                Button {
                    selectedCategory = nil
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
            sortedFilesByCategory: scanVM.sortedFilesByCategory,
            allSortedFiles: scanVM.allSortedFiles,
            selectedCategory: selectedCategory,
            searchQuery: searchQuery,
            isAdvanced: appState.mode == .advanced,
            selectedIDs: cleaningVM.selectedIDs,
            showAllFiles: $showAllFiles,
            onToggle: { [weak cleaningVM] file in cleaningVM?.toggleFile(file) }
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if cleaningVM.selectedCount > 0 {
                Text("^[\(cleaningVM.selectedCount) file](inflect: true) · \(cleaningVM.selectedSize.formattedFileSize)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if appState.mode == .simple {
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
