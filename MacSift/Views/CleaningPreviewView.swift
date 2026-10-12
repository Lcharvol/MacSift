import SwiftUI
import AppKit

struct CleaningPreviewView: View {
    @ObservedObject var cleaningVM: CleaningViewModel
    @ObservedObject var appState: AppState

    /// Show a final destructive confirmation when the user is NOT in dry run.
    @State private var showFinalConfirmation = false
    /// Cached Trash summary, refreshed when the report view appears.
    @State private var trashSummary: TrashService.Summary?
    /// Show a confirmation alert before emptying the Trash.
    @State private var showEmptyTrashConfirmation = false
    /// Whether the empty-trash action has already run in this session.
    @State private var trashEmptied = false
    /// Cached per-category breakdown of the selection, as an array sorted by
    /// `FileCategory.allCases` order so the preview list can render it with a
    /// plain `ForEach` and no dictionary lookups.
    ///
    /// Refreshed ONLY when `cleaningVM.selectionVersion` changes (plus once on
    /// appear) — never inside the body. Reading `cleaningVM.selectedByCategory`
    /// per category in the `ForEach` rebuilt the full grouping 11 times per
    /// render pass, and the sheet re-renders on every `cleaningProgress` tick
    /// during cleaning. On a 50k-file "select all safe" that was seconds of
    /// main-actor work per frame.
    @State private var categoryBreakdown: [CategoryBreakdown] = []

    /// One preview row: a category plus the selected files inside it.
    private struct CategoryBreakdown: Identifiable {
        let category: FileCategory
        let fileCount: Int
        let totalSize: Int64
        var id: FileCategory { category }
    }

    /// 10 GB threshold above which we display an extra warning.
    private static let largeDeletionWarningBytes: Int64 = 10 * 1024 * 1024 * 1024

    /// Build the confirm button label, accounting for grouped selections so the
    /// user understands that one tick may include thousands of underlying files.
    private var confirmButtonLabel: LocalizedStringKey {
        let count = cleaningVM.selectedCount
        let size = cleaningVM.selectedSize.formattedFileSize
        if appState.isDryRun {
            return "Simulate \(count) files (\(size))"
        }
        return "Move to Trash — \(count) files (\(size))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.5)

            Group {
                if cleaningVM.state == .cleaning {
                    cleaningProgressView
                } else if let report = cleaningVM.report {
                    cleaningReportView(report)
                } else {
                    previewContent
                }
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { refreshCategoryBreakdown() }
        .onChange(of: cleaningVM.selectionVersion) { _, _ in
            // Observe the O(1) int counter rather than the Set itself —
            // Set<String> equality on thousands of entries is O(n) per render.
            refreshCategoryBreakdown()
        }
        .alert(
            destructiveAlertTitle,
            isPresented: $showFinalConfirmation,
            actions: {
                Button("Cancel", role: .cancel) { }
                Button("Move to Trash", role: .destructive) {
                    Task { await cleaningVM.confirmCleaning() }
                }
            },
            message: {
                destructiveAlertMessage
            }
        )
    }

    /// Rebuild the cached per-category breakdown. Called from `onAppear` and
    /// from the `selectionVersion` change handler — never from a view body.
    /// One O(selected) pass total, versus 11 per render before.
    private func refreshCategoryBreakdown() {
        let grouped = cleaningVM.groupedSelection()
        categoryBreakdown = FileCategory.allCases.compactMap { category in
            guard let files = grouped[category], !files.isEmpty else { return nil }
            return CategoryBreakdown(
                category: category,
                fileCount: files.count,
                totalSize: files.reduce(0 as Int64) { $0 + $1.size }
            )
        }
    }

    private var destructiveAlertTitle: LocalizedStringKey {
        if cleaningVM.selectedSize >= Self.largeDeletionWarningBytes {
            return "Move \(cleaningVM.selectedSize.formattedFileSize) to the Trash?"
        }
        return "Move \(cleaningVM.selectedCount) files to the Trash?"
    }

    @ViewBuilder
    private var destructiveAlertMessage: some View {
        if cleaningVM.selectedSize >= Self.largeDeletionWarningBytes {
            Text("This is a large deletion (\(cleaningVM.selectedSize.formattedFileSize)). These items will be moved to the Trash. You can restore them from Finder until you empty the Trash.")
        } else {
            Text("These items will be moved to the Trash. You can restore them from Finder until you empty the Trash.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.title2.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") {
                cleaningVM.cancelPreview()
            }
            .keyboardShortcut(.cancelAction)
            .compatGlassButtonStyle()
        }
        .padding(20)
    }

    private var headerTitle: LocalizedStringKey {
        if cleaningVM.state == .cleaning { return "Cleaning..." }
        if cleaningVM.report != nil {
            return appState.isDryRun ? "Dry Run Complete" : "Cleaning Complete"
        }
        return "Review Before Cleaning"
    }

    private var headerSubtitle: LocalizedStringKey {
        if cleaningVM.state == .cleaning { return "Processing files" }
        if cleaningVM.report != nil { return "Summary of the operation" }
        return "Confirm what will be removed"
    }

    // MARK: - Preview

    private var previewContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(categoryBreakdown) { entry in
                        categoryRow(entry)
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.5)

            VStack(spacing: 14) {
                Toggle(isOn: $appState.isDryRun) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Dry Run")
                                .font(.callout.weight(.semibold))
                            Text("Simulate without deleting")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Button {
                    if appState.isDryRun {
                        Task { await cleaningVM.confirmCleaning() }
                    } else {
                        // Require explicit confirmation for destructive deletions
                        showFinalConfirmation = true
                    }
                } label: {
                    Label(confirmButtonLabel, systemImage: appState.isDryRun ? "play" : "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .compatGlassButtonStyle(.prominent)
                .controlSize(.large)
                .tint(appState.isDryRun ? .accentColor : .red)
            }
            .padding(20)
        }
    }

    private func categoryRow(_ entry: CategoryBreakdown) -> some View {
        let category = entry.category
        let categorySize = entry.totalSize

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.displayColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: category.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(category.displayColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .font(.callout.weight(.semibold))
                Text("\(entry.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(category.riskLevel.color)
                    .frame(width: 6, height: 6)
                Text(category.riskLevel.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quinary))

            Text(categorySize.formattedFileSize)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Cleaning progress

    private var cleaningProgressView: some View {
        // Flattened to plain scalars so the subview can be `Equatable` and
        // SwiftUI can skip it when a tick carries no visible change.
        CleaningProgressBody(
            processed: cleaningVM.cleaningProgress?.processed ?? 0,
            total: cleaningVM.cleaningProgress?.total ?? 0,
            currentFile: cleaningVM.cleaningProgress?.currentFile ?? "",
            freedSoFar: cleaningVM.cleaningProgress?.freedSoFar ?? 0,
            hasProgress: cleaningVM.cleaningProgress != nil
        )
        .equatable()
    }

    // MARK: - Report

    private func cleaningReportView(_ report: CleaningReport) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: report.failedFiles.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(report.failedFiles.isEmpty ? .green : .orange)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 4) {
                Text(report.freedSize.formattedFileSize)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()

                reportFilesFreedText(report)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Trash-proof affordance. Confirms (with a tappable path) that
            // files went to ~/.Trash rather than being hard-deleted. The
            // whole row is non-interactive in dry run since there's nothing
            // in the Trash to reveal.
            if !appState.isDryRun, report.deletedCount > 0 {
                trashProofRow(destination: report.firstTrashDestination)
                    .padding(.horizontal, 20)
            }

            if !report.failedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("^[\(report.failedFiles.count) file](inflect: true) could not be deleted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(report.failedFiles.prefix(5).enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.0.name)
                                        .font(.caption.weight(.medium))
                                    Text(item.1)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.orange.opacity(0.15))
                )
                .padding(.horizontal, 20)
            }

            Spacer()

            // Empty Trash affordance — only shown when we freed something real
            // (not a dry run) and the Trash actually has items in it.
            if !appState.isDryRun, let summary = trashSummary, summary.itemCount > 0, !trashEmptied {
                emptyTrashRow(summary: summary)
                    .padding(.horizontal, 20)
            }

            Button {
                cleaningVM.reset()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .compatGlassButtonStyle(.prominent)
            .controlSize(.large)
            .padding(20)
        }
        .task {
            // Refresh the Trash summary when the report view appears.
            // Runs off the main thread because walking the Trash can take a
            // moment on systems with many items.
            trashSummary = await Task.detached(priority: .userInitiated) {
                TrashService.summary()
            }.value
        }
        .alert(
            "Empty the Trash?",
            isPresented: $showEmptyTrashConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Empty Trash", role: .destructive) {
                let freed = TrashService.empty()
                trashEmptied = true
                trashSummary = .init(itemCount: 0, totalSize: 0)
                _ = freed  // reserved for future toast
            }
        } message: {
            let size = trashSummary?.totalSize.formattedFileSize ?? "0 B"
            let count = trashSummary?.itemCount ?? 0
            Text("This permanently removes ^[\(count) item](inflect: true) (\(size)) from your Trash. This cannot be undone.")
        }
    }

    private func reportFilesFreedText(_ report: CleaningReport) -> Text {
        if appState.isDryRun {
            return Text("^[\(report.deletedCount) file](inflect: true) would be freed")
        }
        return Text("^[\(report.deletedCount) file](inflect: true) freed")
    }

    /// Small reassurance row that confirms files were moved to the user's
    /// Trash (not hard-deleted). Shows a `Reveal in Finder` button that opens
    /// `~/.Trash` so the user can see the files with their own eyes. If
    /// `destination` is non-nil we reveal the exact file; otherwise we fall
    /// back to opening the Trash folder.
    private func trashProofRow(destination: URL?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Moved to Trash")
                    .font(.callout.weight(.medium))
                Text("All files went to ~/.Trash. Nothing was permanently deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal in Finder") {
                revealTrash(destination: destination)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quinary)
        )
    }

    private func revealTrash(destination: URL?) {
        let fm = FileManager.default
        if let destination, fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return
        }
        // Fall back to opening the Trash folder itself.
        if let trashURL = try? fm.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            NSWorkspace.shared.open(trashURL)
        }
    }

    private func emptyTrashRow(summary: TrashService.Summary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Finish the job?")
                    .font(.callout.weight(.medium))
                Text("Your Trash contains ^[\(summary.itemCount) item](inflect: true) (\(summary.totalSize.formattedFileSize)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Empty Trash") {
                showEmptyTrashConfirmation = true
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quinary)
        )
    }
}

/// The cleaning-progress body, split out of `CleaningPreviewView` and made
/// `Equatable` so it can be used with `.equatable()`.
///
/// Why this is a separate view: `cleaningProgress` is republished on every
/// engine progress event, and in the dry-run path the engine currently yields
/// once PER FILE with no throttling (see `CleaningEngine.clean`). Every tick
/// invalidates `CleaningPreviewView`, so without this split SwiftUI re-ran the
/// whole sheet body — header, dry-run toggle, and `confirmButtonLabel`, which
/// formats `selectedCount`/`selectedSize` — tens of thousands of times.
///
/// Holding plain scalars (not the non-`Equatable` `CleaningProgress`) lets
/// SwiftUI drop a tick entirely when nothing user-visible moved, and confines
/// the re-render to this subtree when it did. It does NOT fix the per-file
/// main-actor hop itself — that needs throttling in the engine or the
/// ViewModel — it just makes each hop cheap.
private struct CleaningProgressBody: View, Equatable {
    let processed: Int
    let total: Int
    let currentFile: String
    let freedSoFar: Int64
    let hasProgress: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(
                value: Double(processed),
                total: Double(max(total, 1))
            )
            .progressViewStyle(.linear)
            .tint(.blue)
            .padding(.horizontal, 40)

            if hasProgress {
                VStack(spacing: 8) {
                    Text("\(processed) / \(total)")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    Text(currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Freed: \(freedSoFar.formattedFileSize)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
    }
}
