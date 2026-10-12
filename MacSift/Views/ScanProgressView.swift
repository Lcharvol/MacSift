import SwiftUI

struct ScanProgressView: View {
    let progress: ScanDisplayProgress

    @State private var rotate = false

    /// Flips to `true` once the file counters have stopped advancing for
    /// `Self.stallGraceSeconds`, which means enumeration is done and the
    /// ViewModel is in its end-of-scan work (sorting/grouping, listing Time
    /// Machine snapshots, hashing duplicate candidates).
    ///
    /// This is deliberately a VIEW-side inference, not a real phase signal.
    /// `ScanViewModel` publishes only `displayProgress`, so all this view can
    /// honestly observe is "the numbers stopped moving". The copy therefore
    /// says "Finishing up" and lists the remaining work as a single
    /// non-committal line — we never name a specific phase we cannot observe.
    /// See the note on `ScanViewModel.State` in the task write-up for the
    /// phase enum that would let this show the real step.
    @State private var isFinalizing = false

    /// Last progress value we saw advance, plus when we saw it. Compared on
    /// every `progress` change to decide whether the scan has stalled.
    @State private var lastAdvance: Advance = Advance(files: 0, size: 0, at: .distantPast)

    private struct Advance: Equatable {
        var files: Int
        var size: Int64
        var at: Date
    }

    /// How long the counters must sit still before we call it "finishing up".
    /// Long enough that a slow directory or a between-batch lull in the 250ms
    /// throttled update stream doesn't flip the UI, short enough that the user
    /// gets an explanation well before it reads as a hang.
    private static let stallGraceSeconds: TimeInterval = 1.5

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

                Image(systemName: isFinalizing ? "slider.horizontal.3" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(20)
            .compatGlassEffect(in: Circle())
            .onAppear { rotate = true }

            VStack(spacing: 6) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                Text(subheadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                // Two explicit animation pieces working together:
                //  - `contentTransition(.numericText)` tells SwiftUI to
                //    morph digits rather than cross-fade the whole string
                //  - `.animation(value:)` scopes the animation to the
                //    totalSize change and runs slightly shorter than the
                //    250ms update interval from ScanViewModel so each
                //    morph completes before the next delta arrives (0.45s
                //    was too long — each animation was interrupted mid-
                //    way by the next update and the user perceived the
                //    digits as jumping instead of animating).
                Text(progress.totalSize.formattedFileSize)
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeInOut(duration: 0.24), value: progress.totalSize)

                HStack(spacing: 16) {
                    Text("\(progress.totalFiles) files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.easeInOut(duration: 0.24), value: progress.totalFiles)

                    // The per-category label describes where the enumerator
                    // currently is. Once enumeration has stopped it would be
                    // stale, so it is hidden while finalizing.
                    if !isFinalizing, let category = progress.currentCategory {
                        Label(category.label, systemImage: category.iconName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if isFinalizing {
                    finalizingIndicator
                        .frame(maxWidth: 380)
                        .padding(.top, 2)
                } else if !progress.currentPath.isEmpty {
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
        .animation(.easeInOut(duration: 0.28), value: isFinalizing)
        .onAppear { noteAdvance(force: true) }
        .onChange(of: progress) { _, _ in noteAdvance(force: false) }
        .task(id: stallWatchToken) { await watchForStall() }
    }

    // MARK: - Copy

    private var headline: LocalizedStringKey {
        isFinalizing ? "Finishing up" : "Scanning your disk"
    }

    private var subheadline: LocalizedStringKey {
        // Honest phrasing: the view knows enumeration has stopped, but not
        // which end-of-scan step is running right now. So it names the set of
        // remaining work rather than claiming a specific step.
        isFinalizing
            ? "Sorting results, checking snapshots and looking for duplicates"
            : "Categorizing files for transparency"
    }

    /// Indeterminate bar that replaces the current-path line while the
    /// end-of-scan work runs. There is no percentage to show — the work is
    /// not instrumented — so an indeterminate control is the honest control.
    private var finalizingIndicator: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.small)
            .tint(.accentColor)
            .transition(.opacity)
    }

    // MARK: - Stall detection

    /// Token that restarts the stall watcher whenever real progress arrives.
    /// Keying `.task` on it means we only ever have one sleeping watcher, and
    /// it is cancelled and replaced on each advance.
    private var stallWatchToken: Advance { lastAdvance }

    /// Record that progress advanced (or re-arm on first appear). Any forward
    /// movement in either counter clears the finalizing state — a scan that
    /// resumes after a slow directory must go back to "Scanning".
    private func noteAdvance(force: Bool) {
        let advanced = progress.totalFiles != lastAdvance.files
            || progress.totalSize != lastAdvance.size
        guard force || advanced else { return }
        lastAdvance = Advance(files: progress.totalFiles, size: progress.totalSize, at: Date())
        if isFinalizing { isFinalizing = false }
    }

    /// Sleep out the grace period; if nothing cancelled us in the meantime,
    /// the counters have not moved and we are in the end-of-scan work.
    private func watchForStall() async {
        isFinalizing = false
        try? await Task.sleep(for: .seconds(Self.stallGraceSeconds))
        guard !Task.isCancelled else { return }
        isFinalizing = true
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
