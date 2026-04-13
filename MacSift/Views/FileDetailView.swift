import SwiftUI

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
    }
}
