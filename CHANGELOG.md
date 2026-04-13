# Changelog

All notable changes to MacSift are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Downloads double-count bug** shipped in v0.1.2. Files in `~/Downloads`
  that were simultaneously > 500 MB and > 90 days old appeared in both
  `.oldDownloads` and `.largeFiles`. Fix: `scanForLargeFiles` now skips
  `Downloads/` (handled by its own scan target), and the classifier lets
  recent-but-large Downloads files fall through to the `.largeFiles` rule
  so they're still found. Regression tests added.

### Added
- **Freed-space banner** after auto-rescan. "You just freed X GB" green
  banner above the results, auto-dismissed after 5 seconds.
- **Exclude from inspector**: one-click button in the detail panel that
  adds the current folder to the exclusion list.
- **Expand grouped row**: "Show all N files" in the inspector opens a
  drill-down view listing every individual file in the group. Back button
  returns to the grouped view.
- **File list sorting menu** in the toolbar: Size (default), Name, or
  Most Recent. Persisted across launches via `@SceneStorage`.
- **macOS notification** when a long scan finishes in the background.
  Only fires if the scan took > 30s AND the app is not key. Local only,
  zero network.
- **Inspector multi-select mode**: when multiple rows are ticked but no
  single group is selected, the inspector shows an aggregate summary
  (group count, file count, total size, breakdown by category).
- **Dock badge** with the count of safe groups after a scan. Clears on
  new scan.
- **Live storage bar during scanning**: per-category accumulator in
  `ScanDisplayProgress.sizeByCategory`. The scan progress screen now
  shows the breakdown forming in real time as the scan runs.
- **Lifetime stats** in Settings: total scans run + total space cleaned
  since install. Stored in UserDefaults, wiped by the Reset button.
- **Four new scan categories** (shipped in v0.1.2, documented here):
  - **Xcode Junk** — `~/Library/Developer/Xcode/DerivedData`, `Archives`,
    `iOS DeviceSupport`, and `CoreSimulator/Caches`. DerivedData rows are
    grouped per Xcode project (the `-hash` suffix is stripped from the
    folder name).
  - **Dev Caches** — `~/.npm`, `~/.yarn`, `~/.pnpm-store`, `~/.cache/{pip,
    huggingface,yarn}`, `~/.cargo/registry/cache`, `~/.rustup/toolchains`,
    `~/go/pkg/mod`, `~/Library/Caches/Homebrew`. Grouped by package manager
    so you see one row per tool.
  - **Old Downloads** — files in `~/Downloads` that haven't been modified
    in the last 90 days. Age-based rather than size-based, classified as
    `.risky` by default because users often forget what they downloaded
    for a reason.
  - **Mail Attachments** — `~/Library/Mail Downloads` and
    `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`.
    All attachments collapse into a single row.
- **Empty Trash** affordance after a successful real cleaning. The cleaning
  report view shows the current Trash size and offers a one-click "Empty
  Trash" button with its own confirmation alert.
- 12 new classifier tests covering the four new categories.
- Versionless release zip (`MacSift.zip`) so deep links don't break on each release.
- `inaccessibleCount` on `ScanResult`: the results header now reports how many
  files/directories the scanner had to skip due to permissions or I/O errors.
- **Reset all settings** button in Settings. Clears mode, dry-run, threshold,
  and exclusion list with an explicit confirmation alert.
- Open Graph image + Twitter card meta on the landing page.
- Multi-format favicon (`favicon.ico` + 16/32 PNG fallbacks).
- CHANGELOG, SECURITY, and issue / PR templates for the repository.
- Tests for `BundleNames.humanLabel(for:)` and the scan progress delta stream.

### Changed
- `CategoryClassifier.withInstalledApps(largeFileThresholdBytes:)` now builds
  the classifier on a detached task so `/Applications` isn't walked on the
  calling thread. The old synchronous init is kept for tests and trivial cases.
- `CategoryClassifier.sharedHomePrefix` is now exposed to `FileGrouper`, which
  no longer recomputes the home directory prefix on its own.
- `CleaningViewModel.updateFileIndex` cancels any in-flight build before
  starting a new one, fixing a race on rapid re-scans.
- The `build-app.sh` script checks for Swift 6 + macOS 26 prerequisites and
  fails early with a helpful error.

### Fixed
- Scanner no longer silently drops a partial result when one of its parallel
  tasks can't read a directory. The inaccessible count is surfaced in the UI.

## [0.1.0] — 2026-04-13

Initial public release.

### Added
- Disk scanner covering `~/Library/Caches`, `~/Library/Logs`,
  `~/Library/Application Support`, `/tmp`, `/private/var/log`, and the home
  directory (for large files).
- Seven categories: Caches, Logs, Temporary Files, Unused App Data, Large
  Files, Time Machine Snapshots, iOS Backups.
- File grouping by owning app: `Library/Caches/com.apple.Safari/*` collapses
  into a single Safari row, cutting thousands of files down to one decision.
- Orphan detection: `Application Support` folders are only flagged as
  `.appData` if their owning app is no longer installed.
- iOS backups aggregated per-device, with device name + date read from
  each backup's `Info.plist`.
- Inspector panel with Reveal in Finder, Quick Look, Copy Path, and a live
  preview of the top 5 largest files in any selected group.
- Safe cleaning via `FileManager.trashItem`: everything goes to the Finder
  Trash, never a permanent delete.
- Dry run on by default for first-time users. Destructive deletes require
  explicit confirmation; an extra warning fires above 10 GB.
- Cancellable scans, auto-rescan after cleaning, search in the file list,
  drag-and-drop a folder to scan just that folder.
- Keyboard shortcuts: ⌘R scan, ⌘. cancel, ⌘A select all safe, ⌘⇧A deselect,
  Esc dismiss modal.
- Liquid Glass UI using the new macOS 26 (Tahoe) SwiftUI APIs.
- Custom About panel.
- SceneStorage-backed window state restoration for selectedCategory and
  showAllFiles.
- 55 tests across 10 suites.

### Known limitations
- Apple Silicon only.
- Not notarized — first launch requires right-click → Open to bypass
  Gatekeeper. Every subsequent launch is silent (the app is ad-hoc signed,
  so TCC remembers).
- Time Machine snapshot deletion can require admin privileges; the cleaning
  report shows the exact `sudo` command when that happens.
- Dock icon renders slightly smaller than first-party Tahoe apps because
  legacy `.icns` icons aren't the new Icon Composer asset format.
