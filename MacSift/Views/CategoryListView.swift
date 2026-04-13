import SwiftUI

struct CategoryListView: View {
    let sizeByCategory: [FileCategory: Int64]
    let countByCategory: [FileCategory: Int]
    @Binding var selectedCategory: FileCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            Section("Categories") {
                ForEach(FileCategory.allCases) { category in
                    CategoryRow(
                        category: category,
                        size: sizeByCategory[category] ?? 0,
                        count: countByCategory[category] ?? 0
                    )
                    .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct CategoryRow: View {
    let category: FileCategory
    let size: Int64
    let count: Int

    var body: some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.label)
                    if count > 0 {
                        Text("^[\(count) file](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if size > 0 {
                    Text(size.formattedFileSize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .font(.callout)
                }
            }
        } icon: {
            Image(systemName: category.iconName)
                .foregroundStyle(category.displayColor)
        }
    }
}
