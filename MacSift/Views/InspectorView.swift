import SwiftUI
import AppKit
import QuickLookUI

/// Detail panel shown in the right-side inspector when the user single-clicks
/// a file group. Hosts the per-file actions that used to live in a per-row
/// context menu (which was too expensive at scale).
struct InspectorView: View {
    let group: FileGroup?

    var body: some View {
        if let group {
            content(for: group)
        } else {
            placeholder
        }
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
