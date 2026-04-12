import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning...")
                .font(.title2)
                .fontWeight(.semibold)

            if let progress {
                VStack(spacing: 8) {
                    Text("\(progress.filesFound) files found")
                        .font(.headline)

                    Text(progress.currentSize.formattedFileSize)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)

                    if let category = progress.category {
                        Label(category.label, systemImage: category.iconName)
                            .foregroundStyle(category.displayColor)
                    }

                    Text(progress.currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
