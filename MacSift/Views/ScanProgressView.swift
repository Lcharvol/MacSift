import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress?

    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.blue.opacity(0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(.blue.opacity(0.15), lineWidth: 3)
                        .frame(width: 110, height: 110)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                        .animation(
                            .linear(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulse
                        )

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .onAppear { pulse = true }

                VStack(spacing: 6) {
                    Text("Scanning your disk")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("Categorizing files for transparency")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let progress {
                    VStack(spacing: 16) {
                        Text(progress.currentSize.formattedFileSize)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .contentTransition(.numericText())
                            .animation(.easeOut, value: progress.filesFound)

                        HStack(spacing: 18) {
                            Label("\(progress.filesFound) files", systemImage: "doc.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            if let category = progress.category {
                                HStack(spacing: 5) {
                                    Image(systemName: category.iconName)
                                        .foregroundStyle(category.displayColor)
                                    Text(category.label)
                                }
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(category.displayColor.opacity(0.12))
                                )
                            }
                        }

                        Text(progress.currentPath)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 380)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                }
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
