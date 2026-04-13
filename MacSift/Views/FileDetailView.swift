import SwiftUI
import AppKit
import QuickLookUI

struct FileDetailView: View, Equatable {
    let file: ScannedFile
    let isSelected: Bool
    let isAdvanced: Bool
    let onToggle: () -> Void

    // Equatable: SwiftUI re-renders only when these change. The closure is ignored
    // (it captures the same VM and is stable across renders).
    nonisolated static func == (lhs: FileDetailView, rhs: FileDetailView) -> Bool {
        lhs.file.id == rhs.file.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isAdvanced == rhs.isAdvanced
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox — system look, simple
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

            Image(systemName: file.category.iconName)
                .foregroundStyle(file.category.displayColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(isAdvanced ? file.path : file.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(file.size.formattedFileSize)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)

            if isAdvanced {
                Circle()
                    .fill(file.category.riskLevel.color)
                    .frame(width: 6, height: 6)
                    .help(file.category.riskLevel.label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }

            Button {
                QuickLookPreview.show(url: file.url)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            Divider()

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(file.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Quick Look helper

@MainActor
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookPreview()
    private var url: URL?

    static func show(url: URL) {
        shared.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            self.url as NSURL?
        }
    }
}
