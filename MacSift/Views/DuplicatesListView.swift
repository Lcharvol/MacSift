import SwiftUI

/// Detail-pane view shown when the user clicks "Duplicates" in the
/// sidebar. Lists every `DuplicateSet` as a section, with one row per
/// member file. Members feed straight into `CleaningViewModel`'s
/// existing selection store so the regular "Clean Selected" flow
/// handles the actual deletion.
struct DuplicatesListView: View {
    let sets: [DuplicateSet]
    let selectedIDs: Set<String>
    let onToggleFile: (ScannedFile) -> Void
    let onKeepOldest: (DuplicateSet) -> Void

    var body: some View {
        if sets.isEmpty {
            emptyState
        } else {
            List {
                ForEach(sets) { set in
                    Section {
                        ForEach(set.files) { file in
                            row(for: file, in: set)
                        }
                    } header: {
                        header(for: set)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No duplicates found")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Every scanned file larger than 1 MB is unique by content.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(for set: DuplicateSet) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("^[\(set.count) copies](inflect: true) · \(set.size.formattedFileSize) each")
                    .font(.callout.weight(.semibold))
                Text("\(set.wastedBytes.formattedFileSize) reclaimable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button {
                onKeepOldest(set)
            } label: {
                Text("Keep oldest, trash the rest")
                    .font(.caption)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func row(for file: ScannedFile, in set: DuplicateSet) -> some View {
        let isSelected = selectedIDs.contains(file.id)
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(file.modificationDate, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleFile(file) }
    }
}
