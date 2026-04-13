import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress?

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

            if let progress {
                VStack(spacing: 14) {
                    Text(progress.currentSize.formattedFileSize)
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.smooth(duration: 0.45), value: progress.currentSize)

                    HStack(spacing: 16) {
                        Label("\(progress.filesFound) files", systemImage: "doc")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let category = progress.category {
                            Label(category.label, systemImage: category.iconName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

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
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
