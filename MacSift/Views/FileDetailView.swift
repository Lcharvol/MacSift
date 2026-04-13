import SwiftUI

struct FileDetailView: View {
    let file: ScannedFile
    let isSelected: Bool
    let isAdvanced: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
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
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

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
                    .font(.system(.callout, weight: .semibold))
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
                    .font(.system(.callout, design: .rounded, weight: .semibold))
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
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.blue.opacity(0.35) : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.blue.opacity(0.08))
        } else if isHovering {
            return AnyShapeStyle(.quinary)
        } else {
            return AnyShapeStyle(.background.secondary.opacity(0.5))
        }
    }
}
