# Changelog

All notable changes to MacSift are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] — 2026-05-27

### Fixed
- **App crashed on launch in release builds** (#6). SwiftPM's auto-generated
  `Bundle.module` accessor expects the resource bundle at
  `Bundle.main.bundleURL/MacSift_MacSift.bundle` (the `.app` root), but
  `build-app.sh` only copied it under `Contents/Resources/`. The accessor's
  hardcoded absolute build path masked the bug on the developer's own machine,
  so end users were the first to hit the `fatalError` on first localized
  string lookup. `L10n` now routes every lookup through a `resourceBundle`
  static that prefers `Bundle.main` (where the `.lproj` directories are
  already flattened) and only falls back to `Bundle.module` in the test
  runner. Reported by @eryajf.

## [0.4.0] — 2026-05-26

### Added
- **Simplified Chinese localization** (`zh-Hans`). Initial contribution by
  @eryajf in #4, reworked in #5.
- **In-app language picker** in Settings (System / English / Simplified
  Chinese / French). Selecting a language sets `\.locale` on every scene
  so SwiftUI re-renders against the matching `.lproj` bundle. The choice
  is persisted across launches under `appLanguage`.
- **`L10n` helper** for non-SwiftUI call sites (services, view models,
  AppKit interop) that compose strings outside a `View.body` and
  therefore can't rely on the environment locale. Caches resolved
  bundles to keep per-file scan paths cheap; probes lowercase variants
  to handle SwiftPM lowercasing `zh-Hans.lproj` → `zh-hans.lproj` on
  disk.

### Tests
- Test suites that assert against user-facing strings (`FileGrouper`,
  `FileDescriptions`, `CleaningEngine`) are now locale-stable — they
  pin English explicitly instead of depending on the host machine's
  preferred language.

## [0.3.1] — 2026-05-14

### Fixed
- **macOS 15 (Sequoia) compatibility.** Liquid Glass APIs introduced in
  macOS 26 (Tahoe) are now gated behind runtime availability checks via
  `compatGlassEffect` / `compatGlassButtonStyle`. On Sequoia the app
  falls back to `.regularMaterial` / `.bordered` instead of crashing on
  symbol lookup at launch.

## [0.3.0] — 2026-04-15

### Added
- **Duplicate file detection.** A new sidebar entry surfaces sets of
  files that match by content hash (1 MB+ files only). One click on
  "Keep oldest, trash the rest" sends all redundant copies to the
  Trash, sorted by mtime so the original stays put.

## [0.2.11] — 2026-04-15

### Added
- **French localization** (`fr.lproj`). Voice matches the English
  original — direct, honest, no corporate-speak.

### Docs
- Homebrew cask is now the recommended install option.

## [0.2.10] — 2026-04-15

### Security
- **Audit #2 — 10 findings fixed** (H1–H3, M1–M3, L1–L4). Covers
  hardening across the cleaning engine, update checker URL validation,
  and the uninstall flow.

## [0.2.9] — 2026-04-15

### Added
- **In-app uninstall flow** in Settings. Wipes settings, exclusions,
  the audit log, any cached update artifacts, and moves `MacSift.app`
  itself to the Trash — with an explicit confirmation alert and a
  per-step summary. Full Disk Access still has to be revoked manually
  in System Settings.

## [0.2.8] — 2026-04-15

### Security
- **Security audit #1 — 10 findings fixed** (H1–H3, M1–M3, L1–L4).

## [0.2.7] — 2026-04-15

### Removed
- **Dock badge with safe-group count.** It was being read as unread
  notifications and caused more confusion than it was worth.

### Docs
- Project is now MIT-licensed.

## [0.2.6] — 2026-04-15

### Performance
- **Batched trash via `NSWorkspace.recycle`.** Cleaning thousands of
  files now goes through a single AppKit call per chunk instead of
  one `FileManager.trashItem` per file, which was the bottleneck on
  large cache sweeps.

## [0.2.5] — 2026-04-14

### Fixed
- **Scan progress counter froze in multi-volume mode.** Caused by
  cumulative-vs-delta confusion between parallel scan tasks; each task
  now yields its own delta and the view model accumulates them.

## [0.2.4] — 2026-04-14

### Fixed
- **Stale sidebar totals at the start of a new scan.** Volume-filtered
  caches are now cleared at scan start so the previous scan's numbers
  don't bleed into the new one.

## [0.2.3] — 2026-04-14

### Performance
- **Cached volume-filtered views off the render path.** Switching
  between categories no longer rebuilds the filtered file list inside
  `View.body`.

## [0.2.2] — 2026-04-14

### Added
- **Menu bar widget** with live disk / memory / CPU metrics and a
  one-click "Scan now" affordance. The status item is always inserted —
  binding `isInserted:` to a `@Published` produced an infinite rebuild
  loop on macOS 26 that pegged a core at 100% and starved the main
  thread.

### Tests
- +20 tests covering the network layer, the grouper, and `AppState`.
- 8 coverage gaps from the prior audit closed.

## [0.2.1] — 2026-04-14

### Added
- **In-app update banner** with one-click download. Throttled to a
  silent check once every 24h; the banner shows the version delta and
  links to the GitHub release notes.

## [0.2.0] — 2026-04-14

### Added
- **Multi-volume scanning.** A sidebar volume picker lets you target a
  specific external disk or scan everything. The header subtitle and
  totals reflect the selected volume.
- **"Reveal in Finder" affordance** after a real clean, so the user
  can see with their own eyes that files landed in `~/.Trash` rather
  than being hard-deleted.
- **Classifier rules array**, on-disk audit log, plus smoke and perf
  tests.
- **Inaccessible path sampling** in the scan result (up to 10 paths)
  so Full Disk Access errors are diagnosable from the UI.

### Fixed
- **Friendlier error when `trashItem` fails on a locked cache DB.**
  The error message now names the owning app and tells the user to
  quit it and rescan.
- **Lifecycle and observability gaps** from the first audit.

### Docs
- Sequoia Gatekeeper flow documented in README.

## [0.1.4] — 2026-04-13

### Added
- **Configurable Old Downloads age threshold** in Settings. The default
  is still 90 days, but you can now set anything from 1 to 365. Useful
  if you use your Downloads folder as short-term staging (set 7 days)
  or if you prefer a conservative one-year cutoff.

### Performance
- **Selection summary is now cached** in MainView `@State` and recomputed
  only when `selectedIDs` or the completed scan changes. Previously, the
  inspector closure ran `selectionSummary(using: allGroups)` on every
  parent re-render (including every search-field keystroke), which
  iterated every file in every group. On scans with 50k+ files this
  caused visible freezes while typing.
- **`FileGroup.mostRecentModificationDate`** is now pre-computed at scan
  time. The "Most Recent" sort option previously walked every file in
  every group on every render; now it reads a cached `Date`.
- **`freedBanner` dismissal task** cancels the previous timer on
  re-trigger instead of piling up sleeping tasks in memory.
- **`CleaningViewModel.updateFileIndex`** now cancels the detached inner
  task as well as the outer wrapper. Previously, a cancelled index build
  kept walking the file tree to completion because cancellation didn't
  propagate across `Task.detached`.

## [0.1.3] — 2026-04-13

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
