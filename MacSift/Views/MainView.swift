import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scanVM: ScanViewModel
    @StateObject private var cleaningVM: CleaningViewModel
    @State private var selectedCategory: FileCategory?

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
            if newState == .completed {
                cleaningVM.updateFileIndex(from: scanVM.result)
            }
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

            Divider()
                .opacity(0.5)

            sidebarFooter
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
                Task { await scanVM.startScan() }
            } label: {
                Label(
                    scanVM.state == .scanning ? "Scanning..." : "Start Scan",
                    systemImage: scanVM.state == .scanning ? "arrow.triangle.2.circlepath" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(scanVM.state == .scanning)
        }
        .padding(16)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: appState.mode == .simple ? "wand.and.stars" : "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: $appState.mode) {
                    Text("Simple").tag(AppState.Mode.simple)
                    Text("Advanced").tag(AppState.Mode.advanced)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if scanVM.result.totalSize > 0 {
                HStack {
                    Text("Total found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(scanVM.result.totalSize.formattedFileSize)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
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
                Task { await scanVM.startScan() }
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

    private var fileListView: some View {
        // Use pre-sorted cached lists from ScanViewModel — avoids re-sorting on every selection toggle
        let files: [ScannedFile] = {
            if let category = selectedCategory {
                return scanVM.sortedFilesByCategory[category] ?? []
            }
            return scanVM.allSortedFiles
        }()

        // Cap displayed rows for instant category switching. With 10k+ files, even a
        // diffed update is slow; rendering 1k is plenty since the list is sorted by size
        // and users rarely scroll past the top files.
        let displayLimit = 1000
        let displayed = Array(files.prefix(displayLimit))
        let hiddenCount = files.count - displayed.count

        // List wraps NSTableView on macOS — far faster than LazyVStack for thousands of rows.
        // FileDetailView is Equatable so SwiftUI skips re-rendering rows whose props didn't change.
        // .id(selectedCategory) forces List to recreate fresh on category switch instead of
        // running an O(n) diff against the previous array.
        return List {
            ForEach(displayed) { file in
                FileDetailView(
                    file: file,
                    isSelected: cleaningVM.selectedIDs.contains(file.id),
                    isAdvanced: appState.mode == .advanced,
                    onToggle: { cleaningVM.toggleFile(file) }
                )
                .equatable()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
            }

            if hiddenCount > 0 {
                HStack {
                    Spacer()
                    Text("+ \(hiddenCount) smaller files not shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .id(selectedCategory)
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
