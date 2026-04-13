import SwiftUI

/// Replaces the grouped file list temporarily to show every ScannedFile
/// in a single group. Used when the user clicks "Show all N files" in the
/// inspector panel. The close button returns to the normal grouped view.
struct ExpandedGroupView: View {
    let group: FileGroup
    let selectedIDs: Set<String>
    let onToggleFile: (ScannedFile) -> Void
    let onClose: () -> Void

    private var sortedFiles: [ScannedFile] {
        group.files.sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.5)

            List {
                ForEach(sortedFiles) { file in
                    row(for: file)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text("Back to groups")
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(group.label)
                    .font(.callout.weight(.semibold))
                Text("\(group.fileCount) files · \(group.totalSize.formattedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private func row(for file: ScannedFile) -> some View {
        let isSelected = selectedIDs.contains(file.id)
        return HStack(spacing: 12) {
            Button(action: { onToggleFile(file) }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: file.category.iconName)
                .foregroundStyle(file.category.displayColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(file.size.formattedFileSize)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggleFile(file) }
    }
}
