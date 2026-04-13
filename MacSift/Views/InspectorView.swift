import SwiftUI
import AppKit
import QuickLookUI

/// Detail panel shown in the right-side inspector when the user single-clicks
/// a file group. Hosts the per-file actions that used to live in a per-row
/// context menu (which was too expensive at scale).
/// Aggregate of the current multi-selection. When multiple groups are
/// ticked and no single group is being inspected, the inspector shows
/// this summary instead of a per-group detail.
struct SelectionSummary: Sendable {
    let groupCount: Int
    let fileCount: Int
    let totalSize: Int64
    let countByCategory: [FileCategory: Int]
}

struct InspectorView: View {
    let group: FileGroup?
    /// Pre-computed multi-selection summary. Computed upstream only when the
    /// selection actually changes (never per-keystroke), so the inspector's
    /// body can read it cheaply.
    let selectionSummary: SelectionSummary?
    let onExclude: ((URL) -> Void)?
    let onExpand: ((FileGroup) -> Void)?

    @State private var excluded = false

    init(
        group: FileGroup?,
        selectionSummary: SelectionSummary? = nil,
        onExclude: ((URL) -> Void)? = nil,
        onExpand: ((FileGroup) -> Void)? = nil
    ) {
        self.group = group
        self.selectionSummary = selectionSummary
        self.onExclude = onExclude
        self.onExpand = onExpand
    }

    var body: some View {
        if let group {
            content(for: group)
        } else if let summary = selectionSummary, summary.groupCount > 0 {
            multiSelectionContent(for: summary)
        } else {
            placeholder
        }
    }

    // MARK: - Multi-selection summary

    private func multiSelectionContent(for summary: SelectionSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Selection")
                            .font(.headline)
                        Text("^[\(summary.groupCount) group](inflect: true) ticked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    statTile(title: "Total", value: summary.totalSize.formattedFileSize)
                    statTile(title: "Files", value: "\(summary.fileCount)")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Breakdown by category")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(
                    summary.countByCategory
                        .sorted { $0.value > $1.value }
                        .filter { $0.value > 0 },
                    id: \.key
                ) { entry in
                    HStack {
                        Image(systemName: entry.key.iconName)
                            .foregroundStyle(entry.key.displayColor)
                            .frame(width: 16)
                        Text(entry.key.label)
                            .font(.caption)
                        Spacer()
                        Text("\(entry.value)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func content(for group: FileGroup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(for: group)

            Divider()

            actions(for: group)

            if group.isAggregated {
                Divider()
                topFiles(for: group)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(for group: FileGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: group.category.iconName)
                    .font(.title2)
                    .foregroundStyle(group.category.displayColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.label)
                        .font(.headline)
                        .lineLimit(2)
                    Text(group.category.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                statTile(title: "Size", value: group.totalSize == 0 ? "—" : group.totalSize.formattedFileSize)
                statTile(title: "Files", value: "\(group.fileCount)")
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(group.category.riskLevel.color)
                    .frame(width: 6, height: 6)
                Text(group.category.riskLevel.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func actions(for group: FileGroup) -> some View {
        VStack(spacing: 8) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([group.representativeURL])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button {
                QuickLookPreview.show(url: group.representativeURL)
            } label: {
                Label("Quick Look", systemImage: "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(group.representativeURL.path(percentEncoded: false), forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            if group.isAggregated, onExpand != nil {
                Button {
                    onExpand?(group)
                } label: {
                    Label("Show all \(group.fileCount) files", systemImage: "list.bullet.below.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            if onExclude != nil {
                Button {
                    onExclude?(group.representativeURL)
                    excluded = true
                } label: {
                    Label(
                        excluded ? "Excluded from future scans" : "Exclude from future scans",
                        systemImage: excluded ? "checkmark.circle" : "minus.circle"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(excluded)
            }
        }
    }

    private func topFiles(for group: FileGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Largest files in this group")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(group.topFiles, id: \.id) { file in
                HStack {
                    Text(file.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(file.size.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("Select a row")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Pick a file or folder to see details and actions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
