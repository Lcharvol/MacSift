import SwiftUI

struct CategoryListView: View {
    let sizeByCategory: [FileCategory: Int64]
    @Binding var selectedCategory: FileCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(FileCategory.allCases) { category in
                let size = sizeByCategory[category] ?? 0

                Label {
                    HStack {
                        Text(category.label)
                        Spacer()
                        if size > 0 {
                            Text(size.formattedFileSize)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: category.iconName)
                        .foregroundStyle(category.displayColor)
                }
                .tag(category)
            }
        }
    }
}
