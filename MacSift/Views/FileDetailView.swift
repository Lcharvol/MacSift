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
        HStack(spacing: 14) {
            // Checkbox — simple, no animations to keep scrolling smooth
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1.5)
                    )
                    .frame(width: 20, height: 20)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            // Category icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(file.category.displayColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: file.category.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(file.category.displayColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(.callout).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(file.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isAdvanced {
                    Text(file.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(file.size.formattedFileSize)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()

                if isAdvanced {
                    Text(file.modificationDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isAdvanced {
                Circle()
                    .fill(file.category.riskLevel.color)
                    .frame(width: 8, height: 8)
                    .help(file.category.riskLevel.label)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.blue.opacity(0.10) : Color.gray.opacity(0.06))
        )
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
