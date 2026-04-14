import SwiftUI

/// Manages the in-app update flow: version check, banner visibility,
/// download progress. Owned by the root view so the banner survives
/// navigation between idle/scanning/results states.
@MainActor
final class UpdateViewModel: ObservableObject {
    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case readyToInstall(URL)
        case failed(String)
    }

    @Published var availableUpdate: UpdateInfo?
    @Published var downloadState: DownloadState = .idle
    /// User dismissed the banner for this session. Persisted across launches
    /// keyed by the version so a new release re-shows the banner once.
    @Published var dismissedVersion: String? {
        didSet { UserDefaults.standard.set(dismissedVersion, forKey: Self.dismissedKey) }
    }

    private static let dismissedKey = "UpdateViewModel.dismissedVersion"
    private static let lastCheckKey = "UpdateViewModel.lastCheckAt"
    /// How often we ping GitHub. 24h keeps us well under any rate limit
    /// and matches user expectations — once a day is plenty.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Current app version from Info.plist. Falls back to "0.0.0-dev" which
    /// UpdateChecker.compare treats as "always older than latest".
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0-dev"
    }

    init() {
        self.dismissedVersion = UserDefaults.standard.string(forKey: Self.dismissedKey)
    }

    /// True when there's an update AND the user hasn't dismissed this
    /// specific version. Drives whether the banner shows.
    var shouldShowBanner: Bool {
        guard let update = availableUpdate else { return false }
        return update.latestVersion != dismissedVersion
    }

    /// Kick off an update check, respecting the 24h minimum interval unless
    /// the caller passes `force: true`. Silent on failure — the banner just
    /// stays hidden.
    func checkForUpdateIfNeeded(force: Bool = false) async {
        if !force, let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date {
            if Date().timeIntervalSince(last) < Self.checkInterval {
                return
            }
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        do {
            let info = try await UpdateChecker.checkForUpdate(currentVersion: currentVersion)
            self.availableUpdate = info
            if let info {
                MacSiftLog.info("Update available: \(info.latestVersion) (current \(currentVersion))")
            }
        } catch {
            MacSiftLog.warning("Update check failed: \(error)")
        }
    }

    func dismissBanner() {
        dismissedVersion = availableUpdate?.latestVersion
    }

    /// Start downloading the update. Updates `downloadState` as bytes
    /// arrive. On success leaves the state at `.readyToInstall` so the
    /// banner can offer a Reveal-in-Finder button.
    func startDownload() async {
        guard let update = availableUpdate else { return }
        downloadState = .downloading(progress: 0)
        do {
            let appURL = try await UpdateDownloader.downloadAndStage(
                from: update.downloadURL,
                version: update.latestVersion,
                progress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.downloadState = .downloading(progress: fraction)
                    }
                }
            )
            downloadState = .readyToInstall(appURL)
            MacSiftLog.info("Update \(update.latestVersion) downloaded to \(appURL.path(percentEncoded: false))")
        } catch {
            downloadState = .failed("Download failed. Open the release page to try again manually.")
            MacSiftLog.error("Update download failed: \(error)")
        }
    }
}
