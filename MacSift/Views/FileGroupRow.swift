import SwiftUI

/// Row that renders a `FileGroup` (potentially aggregating many files).
/// A group is "selected" when ALL of its underlying files are in the
/// selectedIDs set. Tapping toggles all of them at once.
struct FileGroupRow: View, Equatable {
    let group: FileGroup
    let isSelected: Bool
    let isPartiallySelected: Bool
    let isInspected: Bool
    let isAdvanced: Bool
    let onToggle: () -> Void
    let onInspect: () -> Void

    nonisolated static func == (lhs: FileGroupRow, rhs: FileGroupRow) -> Bool {
        lhs.group.id == rhs.group.id
            && lhs.isSelected == rhs.isSelected
            && lhs.isPartiallySelected == rhs.isPartiallySelected
            && lhs.isInspected == rhs.isInspected
            && lhs.isAdvanced == rhs.isAdvanced
    }

    var body: some View {
        HStack(spacing: 12) {
            checkbox
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }

            Image(systemName: group.category.iconName)
                .foregroundStyle(group.category.displayColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if group.isAggregated {
                    Text("^[\(group.fileCount) file](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isAdvanced {
                    Text(group.representativeURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let first = group.files.first {
                    Text(first.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(displaySize)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)

            if isAdvanced {
                Circle()
                    .fill(group.category.riskLevel.color)
                    .frame(width: 6, height: 6)
                    .help(group.category.riskLevel.label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowFill)
        )
        .contentShape(Rectangle())
        .onTapGesture { onInspect() }
    }

    private var rowFill: Color {
        if isInspected { return Color.accentColor.opacity(0.18) }
        if isSelected { return Color.accentColor.opacity(0.10) }
        return Color.clear
    }

    @ViewBuilder
    private var checkbox: some View {
        let symbol: String = {
            if isSelected { return "checkmark.circle.fill" }
            if isPartiallySelected { return "minus.circle.fill" }
            return "circle"
        }()
        let color: Color = (isSelected || isPartiallySelected) ? .accentColor : .secondary.opacity(0.5)
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(color)
    }

    /// Time Machine snapshots and other entries with no measurable size show
    /// "—" instead of a misleading "0 B".
    private var displaySize: String {
        if group.category == .timeMachineSnapshots && group.totalSize == 0 {
            return "—"
        }
        return group.totalSize.formattedFileSize
    }
}
