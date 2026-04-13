import SwiftUI

struct ScanProgressView: View {
    let progress: ScanDisplayProgress

    @State private var rotate = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
                    .frame(width: 96, height: 96)

                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(rotate ? 360 : 0))
                    .animation(
                        .linear(duration: 1.6).repeatForever(autoreverses: false),
                        value: rotate
                    )

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .glassEffect(.regular, in: Circle())
            .onAppear { rotate = true }

            VStack(spacing: 6) {
                Text("Scanning your disk")
                    .font(.title2.weight(.semibold))
                Text("Categorizing files for transparency")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                Text(progress.totalSize.formattedFileSize)
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.smooth(duration: 0.45), value: progress.totalSize)

                HStack(spacing: 16) {
                    Label("\(progress.totalFiles) files", systemImage: "doc")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let category = progress.currentCategory {
                        Label(category.label, systemImage: category.iconName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !progress.currentPath.isEmpty {
                    Text(progress.currentPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 380)
                        .id(progress.currentPath)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: progress.currentPath)
                }

                // Live per-category storage bar. Renders as soon as any
                // category has something, which gives immediate visual
                // feedback that the scan is making progress.
                if !progress.sizeByCategory.isEmpty {
                    liveStorageBar(from: progress.sizeByCategory)
                        .frame(maxWidth: 380)
                        .padding(.top, 8)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveStorageBar(from sizes: [FileCategory: Int64]) -> some View {
        let sorted = sizes
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        let total = max(sorted.reduce(0 as Int64) { $0 + $1.value }, 1)

        return GeometryReader { geo in
            let w = geo.size.width
            let spacing: CGFloat = 2
            HStack(spacing: spacing) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { _, entry in
                    let fraction = CGFloat(entry.value) / CGFloat(total)
                    Rectangle()
                        .fill(entry.key.displayColor)
                        .frame(width: max(4, w * fraction - spacing))
                        .opacity(0.9)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.3), value: sorted.count)
    }
}
