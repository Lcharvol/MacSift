import SwiftUI

/// How the file list is ordered. Persisted via @SceneStorage in MainView.
enum FileListSortOption: String, CaseIterable, Identifiable {
    case sizeDesc
    case nameAsc
    case dateDesc

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sizeDesc: L10n.text("sort.sizeDesc", defaultValue: "Size (largest first)")
        case .nameAsc: L10n.text("sort.nameAsc", defaultValue: "Name (A-Z)")
        case .dateDesc: L10n.text("sort.mostRecent", defaultValue: "Most recent first")
        }
    }
}

/// Isolated view for the file list. Renders aggregated `FileGroup`s instead
/// of raw files so that things like "Safari cache" appear as a single row
/// even when they contain thousands of underlying files.
struct FileListSection: View {
    let groupsByCategory: [FileCategory: [FileGroup]]
    let allSortedGroups: [FileGroup]
    let selectedCategory: FileCategory?
    let searchQuery: String
    let isAdvanced: Bool
    let sortOption: FileListSortOption
    let selectedIDs: Set<String>
    let inspectedGroupID: String?
    @Binding var showAllFiles: Bool
    let onToggleGroup: (FileGroup) -> Void
    let onInspectGroup: (FileGroup) -> Void

    private static let defaultCap = 300

    private var displayedGroups: [FileGroup] {
        let baseGroups: [FileGroup] = {
            if let category = selectedCategory {
                return groupsByCategory[category] ?? []
            }
            return allSortedGroups
        }()

        let filtered: [FileGroup] = {
            let q = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return baseGroups }
            return baseGroups.filter { $0.label.lowercased().contains(q) }
        }()

        let sorted: [FileGroup] = {
            switch sortOption {
            case .sizeDesc:
                // The base array is already sorted by size desc in ScanViewModel,
                // so this is a no-op when the sort hasn't changed.
                return filtered.sorted { $0.totalSize > $1.totalSize }
            case .nameAsc:
                return filtered.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            case .dateDesc:
                // Use the pre-computed mostRecentModificationDate so we
                // don't walk every file per render.
                return filtered.sorted {
                    $0.mostRecentModificationDate > $1.mostRecentModificationDate
                }
            }
        }()

        let limit = showAllFiles ? Int.max : Self.defaultCap
        return Array(sorted.prefix(limit))
    }

    private var totalAvailable: Int {
        if let category = selectedCategory {
            return groupsByCategory[category]?.count ?? 0
        }
        return allSortedGroups.count
    }

    var body: some View {
        let displayed = displayedGroups
        let hidden = max(0, totalAvailable - displayed.count)

        if displayed.isEmpty && searchQuery.isEmpty {
            FileListEmptyState(category: selectedCategory)
        } else if displayed.isEmpty {
            FileListNoMatchesState(query: searchQuery)
        } else {
            List {
                ForEach(displayed) { group in
                    let groupIDs = group.fileIDs
                    let allSelected = !groupIDs.isEmpty && groupIDs.isSubset(of: selectedIDs)
                    let anySelected = !groupIDs.isDisjoint(with: selectedIDs)
                    let partiallySelected = anySelected && !allSelected

                    FileGroupRow(
                        group: group,
                        isSelected: allSelected,
                        isPartiallySelected: partiallySelected,
                        isInspected: inspectedGroupID == group.id,
                        isAdvanced: isAdvanced,
                        onToggle: { onToggleGroup(group) },
                        onInspect: { onInspectGroup(group) }
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
                            Text(L10n.format(
                                "+ %d smaller groups not shown",
                                defaultValue: "+ %d smaller groups not shown",
                                hidden
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Show all") {
                                showAllFiles = true
                            }
                            .compatGlassButtonStyle()
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if showAllFiles && totalAvailable > Self.defaultCap {
                    HStack {
                        Spacer()
                        Button("Show less") {
                            showAllFiles = false
                        }
                        .compatGlassButtonStyle()
                        .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Your disk looks clean for this category.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        guard let category else {
            return L10n.text("No files found", defaultValue: "No files found")
        }
        return L10n.format("No %@ found", defaultValue: "No %@ found", category.label.lowercased())
    }
}

private struct FileListNoMatchesState: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(L10n.format("No matches for \"%@\"", defaultValue: "No matches for \"%@\"", query))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
