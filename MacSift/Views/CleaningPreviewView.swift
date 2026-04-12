import SwiftUI

struct CleaningPreviewView: View {
    @ObservedObject var cleaningVM: CleaningViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cleaning Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") {
                    cleaningVM.cancelPreview()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if cleaningVM.state == .cleaning {
                cleaningProgressView
            } else if let report = cleaningVM.report {
                cleaningReportView(report)
            } else {
                previewContent
            }
        }
        .frame(width: 550, height: 450)
    }

    private var previewContent: some View {
        VStack(spacing: 16) {
            List {
                ForEach(FileCategory.allCases) { category in
                    let files = cleaningVM.selectedByCategory[category] ?? []
                    if !files.isEmpty {
                        let categorySize = files.reduce(0 as Int64) { $0 + $1.size }
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundStyle(category.displayColor)
                            Text(category.label)
                            Spacer()
                            Circle()
                                .fill(category.riskLevel.color)
                                .frame(width: 8, height: 8)
                            Text("\(files.count) files")
                                .foregroundStyle(.secondary)
                            Text(categorySize.formattedFileSize)
                                .fontWeight(.medium)
                        }
                    }
                }
            }

            Toggle("Dry Run (simulate only)", isOn: $appState.isDryRun)
                .padding(.horizontal)

            if appState.isDryRun {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Dry run mode: no files will actually be deleted.")
                        .font(.callout)
                }
                .padding(.horizontal)
            }

            Button {
                Task { await cleaningVM.confirmCleaning() }
            } label: {
                Text("Delete \(cleaningVM.selectedCount) files (\(cleaningVM.selectedSize.formattedFileSize))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isDryRun ? .blue : .red)
            .controlSize(.large)
            .padding()
        }
    }

    private var cleaningProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(
                value: Double(cleaningVM.cleaningProgress?.processed ?? 0),
                total: Double(cleaningVM.cleaningProgress?.total ?? 1)
            )
            .padding(.horizontal)

            if let progress = cleaningVM.cleaningProgress {
                Text("Processing \(progress.processed)/\(progress.total)")
                    .font(.headline)
                Text(progress.currentFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Freed: \(progress.freedSoFar.formattedFileSize)")
                    .font(.callout)
            }

            Spacer()
        }
    }

    private func cleaningReportView(_ report: CleaningReport) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: report.failedFiles.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(report.failedFiles.isEmpty ? .green : .orange)

            Text(appState.isDryRun ? "Dry Run Complete" : "Cleaning Complete")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 4) {
                Text("\(report.deletedCount) files \(appState.isDryRun ? "would be" : "") deleted")
                Text("\(report.freedSize.formattedFileSize) \(appState.isDryRun ? "would be" : "") freed")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            if !report.failedFiles.isEmpty {
                Divider()
                Text("\(report.failedFiles.count) files could not be deleted:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List(Array(report.failedFiles.prefix(10).enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading) {
                        Text(item.0.name)
                            .fontWeight(.medium)
                        Text(item.1)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()

            Button("Done") {
                cleaningVM.reset()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
