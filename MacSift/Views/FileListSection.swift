import SwiftUI

/// Isolated view for the file list. By taking its inputs as plain values and
/// not observing the ViewModels directly, SwiftUI can skip re-evaluating the
/// list when unrelated parent state changes. The cap on displayed rows keeps
/// category switches snappy even with very large categories.
struct FileListSection: View {
    let sortedFilesByCategory: [FileCategory: [ScannedFile]]
    let allSortedFiles: [ScannedFile]
    let selectedCategory: FileCategory?
    let searchQuery: String
    let isAdvanced: Bool
    let selectedIDs: Set<String>
    @Binding var showAllFiles: Bool
    let onToggle: (ScannedFile) -> Void

    private static let defaultCap = 300

    private var displayedFiles: [ScannedFile] {
        let baseFiles: [ScannedFile] = {
            if let category = selectedCategory {
                return sortedFilesByCategory[category] ?? []
            }
            return allSortedFiles
        }()

        let filtered: [ScannedFile] = {
            let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return baseFiles }
            return baseFiles.filter { $0.name.lowercased().contains(q) }
        }()

        let limit = showAllFiles ? Int.max : Self.defaultCap
        return Array(filtered.prefix(limit))
    }

    private var totalAvailable: Int {
        if let category = selectedCategory {
            return sortedFilesByCategory[category]?.count ?? 0
        }
        return allSortedFiles.count
    }

    var body: some View {
        let displayed = displayedFiles
        let hidden = max(0, totalAvailable - displayed.count)

        if displayed.isEmpty && searchQuery.isEmpty {
            FileListEmptyState(category: selectedCategory)
        } else if displayed.isEmpty {
            FileListNoMatchesState(query: searchQuery)
        } else {
            List {
                ForEach(displayed) { file in
                    FileDetailView(
                        file: file,
                        isSelected: selectedIDs.contains(file.id),
                        isAdvanced: isAdvanced,
                        onToggle: { onToggle(file) }
                    )
                    .equatable()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                }

                if hidden > 0 {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Text("+ \(hidden) smaller files not shown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Show all") {
                                showAllFiles = true
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Disable list animations: we don't want diff-based row insert/delete
            // animations when the user switches categories.
            .animation(.none, value: selectedCategory)
        }
    }
}

private struct FileListEmptyState: View {
    let category: FileCategory?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(category == nil ? "No files found" : "No \(category!.label.lowercased()) found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your disk looks clean for this category.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileListNoMatchesState: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No matches for \"\(query)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
