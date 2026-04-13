import SwiftUI

struct CategoryListView: View {
    let sizeByCategory: [FileCategory: Int64]
    @Binding var selectedCategory: FileCategory?

    private var maxSize: Int64 {
        max(sizeByCategory.values.max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Text("CATEGORIES")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(FileCategory.allCases) { category in
                    CategoryRow(
                        category: category,
                        size: sizeByCategory[category] ?? 0,
                        maxSize: maxSize,
                        isSelected: selectedCategory == category
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }
}

private struct CategoryRow: View {
    let category: FileCategory
    let size: Int64
    let maxSize: Int64
    let isSelected: Bool

    @State private var isHovering = false

    private var fillFraction: CGFloat {
        guard maxSize > 0 else { return 0 }
        return CGFloat(Double(size) / Double(maxSize))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(category.displayColor.opacity(isSelected ? 0.25 : 0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: category.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(category.displayColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.label)
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if size > 0 {
                        Text(size.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            if size > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: 3)
                        Capsule()
                            .fill(category.displayColor)
                            .frame(width: max(4, geo.size.width * fillFraction), height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? category.displayColor.opacity(0.4) : .clear, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var backgroundFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(category.displayColor.opacity(0.12))
        } else if isHovering {
            return AnyShapeStyle(.quinary)
        } else {
            return AnyShapeStyle(.clear)
        }
    }
}
