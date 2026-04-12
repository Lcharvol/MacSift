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
            VStack(spacing: 0) {
                Button {
                    Task { await scanVM.startScan() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 8)
                .disabled(scanVM.state == .scanning)

                CategoryListView(
                    sizeByCategory: scanVM.result.sizeByCategory,
                    selectedCategory: $selectedCategory
                )

                Divider()

                Picker("Mode", selection: $appState.mode) {
                    Text("Simple").tag(AppState.Mode.simple)
                    Text("Advanced").tag(AppState.Mode.advanced)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailContent
        }
        .sheet(isPresented: $cleaningVM.showPreview) {
            CleaningPreviewView(cleaningVM: cleaningVM, appState: appState)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch scanVM.state {
        case .idle:
            welcomeView
        case .scanning:
            ScanProgressView(progress: scanVM.progress)
        case .completed:
            resultsView
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("MacSift")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Scan your disk to find unnecessary files")
                .foregroundStyle(.secondary)

            if !scanVM.hasFullDiskAccess {
                fullDiskAccessBanner
            }

            Button {
                Task { await scanVM.startScan() }
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Full Disk Access not granted. Some files may not be scanned.")
                .font(.callout)
            Spacer()
            Button("Open Settings") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 40)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            TreemapView(
                result: scanVM.result,
                selectedCategory: $selectedCategory
            )
            .frame(height: 250)

            Divider()

            fileListView

            bottomBar
        }
    }

    private var fileListView: some View {
        let files: [ScannedFile] = {
            if let category = selectedCategory {
                return (scanVM.result.filesByCategory[category] ?? []).sorted { $0.size > $1.size }
            }
            return scanVM.result.filesByCategory.values.flatMap { $0 }.sorted { $0.size > $1.size }
        }()

        return List(files) { file in
            FileDetailView(
                file: file,
                isSelected: cleaningVM.selectedFiles.contains(file),
                isAdvanced: appState.mode == .advanced,
                onToggle: { cleaningVM.toggleFile(file) }
            )
        }
    }

    private var bottomBar: some View {
        HStack {
            if cleaningVM.selectedCount > 0 {
                Text("\(cleaningVM.selectedCount) files selected (\(cleaningVM.selectedSize.formattedFileSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.mode == .simple {
                Button("Select All Safe") {
                    cleaningVM.selectAllSafe(from: scanVM.result)
                }
                .buttonStyle(.bordered)
            }

            Button("Clean Selected") {
                cleaningVM.showCleaningPreview()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(cleaningVM.selectedFiles.isEmpty)
        }
        .padding()
        .background(.bar)
    }
}
