import SwiftUI

struct CleaningPreviewView: View {
    @ObservedObject var cleaningVM: CleaningViewModel
    @ObservedObject var appState: AppState

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
        }
        .padding(20)
    }

    private var headerTitle: String {
        if cleaningVM.state == .cleaning { return "Cleaning..." }
        if cleaningVM.report != nil { return appState.isDryRun ? "Dry Run Complete" : "Cleaning Complete" }
        return "Review Before Cleaning"
    }

    private var headerSubtitle: String {
        if cleaningVM.state == .cleaning { return "Processing files" }
        if cleaningVM.report != nil { return "Summary of the operation" }
        return "Confirm what will be removed"
    }

    // MARK: - Preview

    private var previewContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(FileCategory.allCases) { category in
                        let files = cleaningVM.selectedByCategory[category] ?? []
                        if !files.isEmpty {
                            categoryRow(category: category, files: files)
                        }
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
                    Task { await cleaningVM.confirmCleaning() }
                } label: {
                    Label(
                        appState.isDryRun
                            ? "Simulate \(cleaningVM.selectedCount) files (\(cleaningVM.selectedSize.formattedFileSize))"
                            : "Delete \(cleaningVM.selectedCount) files (\(cleaningVM.selectedSize.formattedFileSize))",
                        systemImage: appState.isDryRun ? "play" : "trash"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(appState.isDryRun ? .accentColor : .red)
            }
            .padding(20)
        }
    }

    private func categoryRow(category: FileCategory, files: [ScannedFile]) -> some View {
        let categorySize = files.reduce(0 as Int64) { $0 + $1.size }

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
                Text("\(files.count) files")
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
        VStack(spacing: 24) {
            Spacer()

            ProgressView(
                value: Double(cleaningVM.cleaningProgress?.processed ?? 0),
                total: Double(cleaningVM.cleaningProgress?.total ?? 1)
            )
            .progressViewStyle(.linear)
            .tint(.blue)
            .padding(.horizontal, 40)

            if let progress = cleaningVM.cleaningProgress {
                VStack(spacing: 8) {
                    Text("\(progress.processed) / \(progress.total)")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    Text(progress.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Freed: \(progress.freedSoFar.formattedFileSize)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
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

                Text("\(report.deletedCount) files \(appState.isDryRun ? "would be " : "")freed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !report.failedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(report.failedFiles.count) files could not be deleted")
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
                        .fill(.orange.opacity(0.08))
                )
                .padding(.horizontal, 20)
            }

            Spacer()

            Button {
                cleaningVM.reset()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(20)
        }
    }
}
