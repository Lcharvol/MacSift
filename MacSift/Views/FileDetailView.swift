import SwiftUI

struct FileDetailView: View {
    let file: ScannedFile
    let isSelected: Bool
    let isAdvanced: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Image(systemName: file.category.iconName)
                .foregroundStyle(file.category.displayColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

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

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(file.size.formattedFileSize)
                    .fontWeight(.medium)
                    .font(.callout)

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
        .padding(.vertical, 4)
    }
}
