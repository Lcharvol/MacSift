import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress?

    @State private var rotate = false
    @State private var breathe = false
    @State private var glow = false

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

            VStack(spacing: 32) {
                ZStack {
                    // Outer breathing glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.18), .purple.opacity(0.08), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(glow ? 1.08 : 0.92)
                        .opacity(glow ? 0.9 : 0.5)
                        .blur(radius: 12)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: glow
                        )

                    // Track ring
                    Circle()
                        .stroke(.blue.opacity(0.10), lineWidth: 2.5)
                        .frame(width: 118, height: 118)

                    // Animated arc with gradient tail
                    Circle()
                        .trim(from: 0, to: 0.55)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .blue.opacity(0.0), location: 0.0),
                                    .init(color: .blue.opacity(0.6), location: 0.35),
                                    .init(color: .purple, location: 1.0),
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 118, height: 118)
                        .rotationEffect(.degrees(rotate ? 360 : 0))
                        .animation(
                            .linear(duration: 3.2).repeatForever(autoreverses: false),
                            value: rotate
                        )

                    // Subtle inner ring (counter-rotating, slower)
                    Circle()
                        .trim(from: 0, to: 0.15)
                        .stroke(
                            .purple.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(rotate ? -360 : 0))
                        .animation(
                            .linear(duration: 4.8).repeatForever(autoreverses: false),
                            value: rotate
                        )

                    // Breathing icon
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(breathe ? 1.05 : 0.97)
                        .animation(
                            .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                            value: breathe
                        )
                }
                .onAppear {
                    rotate = true
                    breathe = true
                    glow = true
                }

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
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.smooth(duration: 0.45), value: progress.currentSize)

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
                            .id(progress.currentPath)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: progress.currentPath)
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
