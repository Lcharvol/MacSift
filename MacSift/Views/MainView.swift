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
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("MacSift")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
            }

            Button {
                Task { await scanVM.startScan() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: scanVM.state == .scanning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text(scanVM.state == .scanning ? "Scanning..." : "Start Scan")
                        .font(.system(.body, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .foregroundStyle(.white)
                .shadow(color: .blue.opacity(0.25), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
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
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
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
            ScanProgressView(progress: scanVM.progress)
        case .completed:
            resultsView
        }
    }

    private var welcomeView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.15), .purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)

                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text("Welcome to MacSift")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Discover what's taking up space, with full transparency.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !scanVM.hasFullDiskAccess {
                    fullDiskAccessBanner
                }

                Button {
                    Task { await scanVM.startScan() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Start Scan")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .foregroundStyle(.white)
                    .shadow(color: .blue.opacity(0.35), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(40)
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access Required")
                    .font(.callout.weight(.semibold))
                Text("Some system files won't be scanned without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Grant Access") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .frame(maxWidth: 480)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader

            TreemapView(
                result: scanVM.result,
                selectedCategory: $selectedCategory
            )
            .frame(height: 240)
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
                    .font(.system(.title2, design: .rounded, weight: .bold))
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
        let files: [ScannedFile] = {
            if let category = selectedCategory {
                return (scanVM.result.filesByCategory[category] ?? []).sorted { $0.size > $1.size }
            }
            return scanVM.result.filesByCategory.values.flatMap { $0 }.sorted { $0.size > $1.size }
        }()

        return ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(files) { file in
                    FileDetailView(
                        file: file,
                        isSelected: cleaningVM.selectedFiles.contains(file),
                        isAdvanced: appState.mode == .advanced,
                        onToggle: { cleaningVM.toggleFile(file) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollContentBackground(.hidden)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if cleaningVM.selectedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(cleaningVM.selectedCount) selected")
                            .font(.system(.callout, weight: .semibold))
                        Text(cleaningVM.selectedSize.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.blue.opacity(0.1))
                )
            }

            Spacer()

            if appState.mode == .simple {
                Button {
                    cleaningVM.selectAllSafe(from: scanVM.result)
                } label: {
                    Label("Select all safe", systemImage: "checkmark.shield.fill")
                        .font(.system(.callout, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                cleaningVM.showCleaningPreview()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash.fill")
                    Text("Clean Selected")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(cleaningVM.selectedFiles.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}
