import Foundation
import UserNotifications
import AppKit

/// Post a local macOS notification when a long scan completes in the
/// background. Local only — no network calls, consistent with our
/// zero-telemetry commitment.
///
/// Authorization is requested lazily on the first long scan so users who
/// never trigger a notification never see a prompt.
enum ScanNotifications {
    /// Scans shorter than this are considered "fast enough to not need a
    /// notification". Prevents notification spam on trivial scans.
    static let longScanThresholdSeconds: TimeInterval = 30

    /// Call once on scan completion. Posts a notification only if:
    /// - the scan took longer than the threshold, and
    /// - the app is not currently key (i.e., the user has tabbed away).
    @MainActor
    static func notifyIfBackgroundLongScan(
        duration: TimeInterval,
        fileCount: Int,
        totalSize: Int64
    ) {
        guard duration >= longScanThresholdSeconds else { return }
        guard !NSApp.isActive else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            // Request authorization the first time we actually need it.
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "MacSift · Scan complete"
            content.body = "\(fileCount) files · \(totalSize.formattedFileSize) recoverable"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "MacSift.scanComplete.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
