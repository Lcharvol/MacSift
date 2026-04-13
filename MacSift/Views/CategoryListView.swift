import SwiftUI

struct CategoryListView: View {
    let sizeByCategory: [FileCategory: Int64]
    @Binding var selectedCategory: FileCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            Section("Categories") {
                ForEach(FileCategory.allCases) { category in
                    CategoryRow(
                        category: category,
                        size: sizeByCategory[category] ?? 0
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

    var body: some View {
        Label {
            HStack {
                Text(category.label)
                Spacer()
                if size > 0 {
                    Text(size.formattedFileSize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: category.iconName)
                .foregroundStyle(category.displayColor)
        }
    }
}
