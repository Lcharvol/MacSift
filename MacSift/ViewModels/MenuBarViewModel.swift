import SwiftUI

/// Drives the menu bar popover: samples `SystemMetrics` on a timer, plus
/// exposes a one-line summary used in the menu bar title when the user
/// opts in to "show numbers in the menu bar" (deferred — for v1 we use
/// just an icon).
///
/// Refresh cadence is adaptive: 2 seconds while the popover is open
/// (live updates for CPU/RAM) and 30 seconds while it's closed (just
/// keeping the disk number fresh for the icon and any background UI).
@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var metrics: SystemMetrics = .zero
    @Published var isPopoverOpen = false

    private let reader = SystemMetricsReader()
    private var refreshTask: Task<Void, Never>?

    init() {
        // Take one snapshot immediately so the initial view has real
        // numbers instead of zeros. Note the CPU delta is zero on first
        // sample by design — it picks up on the second tick.
        metrics = reader.snapshot()
        startRefreshLoop()
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Call from the popover's `onAppear` / `onDisappear` so the sampler
    /// can switch cadence. While the popover is open we sample every 2s
    /// for snappy CPU/RAM updates; while hidden we drop to 30s to avoid
    /// wasting battery.
    func setPopoverVisible(_ visible: Bool) {
        isPopoverOpen = visible
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: UInt64 = (self?.isPopoverOpen ?? false) ? 2_000_000_000 : 30_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard let self, !Task.isCancelled else { return }
                let snapshot = self.reader.snapshot()
                self.metrics = snapshot
            }
        }
    }
}
