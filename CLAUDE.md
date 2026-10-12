# MacSift — Working Notes for Claude

Transparent macOS disk cleaning utility. SwiftUI, MVVM, built with SwiftPM (no Xcode project file). Deployment target is macOS 15 (Sequoia); Liquid Glass APIs from macOS 26 (Tahoe) are gated behind runtime availability checks via the `compatGlassEffect` / `compatGlassButtonStyle` helpers in `Utilities/GlassCompat.swift`.

## Build / run / test

```bash
# Compile only (fast, for type-checking)
swift build

# Run the full test suite
swift test

# Run a single suite
swift test --filter CleaningEngineIntegrationTests

# Build the .app bundle and launch (this is how the user runs it)
./build-app.sh
open MacSift.app
```

`build-app.sh` produces a proper `.app` bundle (with `Info.plist` + `AppIcon.icns`) from the SPM build output, ad-hoc signs it for stable TCC identity, and prints next steps. The bundle path is `MacSift.app/` at the repo root and is gitignored.

The user is on macOS 26.2 / Xcode 26.3. Deployment target is macOS 15.0 (Sequoia). On Sequoia the app falls back to `.regularMaterial` / `.bordered` instead of Liquid Glass.

## Project layout

```
MacSift/
├── App/                   # MacSiftApp entry point + AppState (@Published mode, dryRun, threshold)
├── Models/                # FileCategory, ScannedFile, ScanResult, FileGroup — pure value types, Sendable
├── Services/              # DiskScanner, CategoryClassifier, FileGrouper, CleaningEngine,
│                            TimeMachineService, ExclusionManager
├── ViewModels/            # ScanViewModel, CleaningViewModel — @MainActor, @Published, orchestrate services
├── Views/                 # SwiftUI views — WelcomeView, ScanProgressView, FileListSection,
│                            FileGroupRow, InspectorView, MainView, …
└── Utilities/             # FileSize+Formatting, FileDescriptions, BundleNames, Permissions
```

Keep the structure flat. Don't introduce package boundaries or sub-frameworks.

## File grouping architecture

`ScannedFile` is one underlying OS file. `FileGroup` is a display-layer
aggregation — multiple ScannedFiles that share a common owner (e.g., all files
under `~/Library/Caches/com.apple.Safari/` collapse into one "Safari" row).

- **`FileGrouper`** (Services) turns `[ScannedFile]` into `[FileGroup]` using
  per-category rules:
    - `.cache` / `.logs` / `.appData`: group by the first path component after
      `Library/<root>/` (the bundle id / folder name).
    - `.iosBackups`: group by the backup root folder under `MobileSync/Backup/`.
    - `.timeMachineSnapshots`: already 1:1 (each snapshot is one synthetic file).
    - `.tempFiles` / `.largeFiles`: kept as singleton groups.
- **Selection is still file-level** (`CleaningViewModel.selectedIDs: Set<String>`).
  Toggling a group selects/deselects all its underlying file ids at once via
  `toggleGroup`. A group is "fully selected" when all its file ids are in the
  selection set, "partially selected" when some are.
- **`FileGroup.topFiles`** is pre-computed at scan time (top N by size, via a
  partial sort). The inspector reads it directly — never sort the full
  `group.files` array in a view body.
- **`BundleNames.humanLabel(for:)`** translates `com.apple.Safari` → "Safari".
  Known apps are matched first; unknown reverse-DNS ids fall through to a
  heuristic that picks the most meaningful segment.
- **Rendering**: `FileListSection` renders `FileGroupRow`s, not individual files.
  Singleton groups still appear as one-row entries.

## Conventions

- **MVVM, strict.** Views render state and call methods; never call services directly.
- **Models are `struct` + `Sendable`.** No reference types in the data flow.
- **Services are `struct` or `enum`** unless they genuinely need identity (none currently do — `DiskScanner` was an actor and got demoted).
- **ViewModels are `@MainActor final class`** with `@Published` properties. Heavy work hops off main via `Task.detached`.
- **No emojis in code.** Sparingly in commit messages and only when it adds info.
- **No `design: .rounded` fonts.** We removed all of them — system semibold is the house style.
- **No gradients.** Use `.tint`, `.accentColor`, system materials. Liquid Glass is applied via the `.compatGlassEffect(in:)` and `.compatGlassButtonStyle(_:)` helpers — never call `.glassEffect` or `.buttonStyle(.glass)` directly, as those only exist on macOS 26 and the app supports macOS 15+.
- **Use `.monospacedDigit()` on every number** that updates frequently (sizes, counters) to avoid jitter.

## Performance lessons (read before touching the file list)

We've already paid for these. Don't undo them without a good reason.

1. **Pre-sort once at end of scan, cache in `ScanViewModel.sortedFilesByCategory` and `allSortedFiles`.** Never sort in a `View.body`.
2. **Selection is `Set<String>` (file id), not `Set<ScannedFile>`.** The id is a stable SHA-256 of the URL path, derived in `ScannedFile.init`. Stable across re-scans.
3. **`FileDetailView` is `Equatable`** and used with `.equatable()`. The `==` ignores closures and only compares `file.id`, `isSelected`, `isAdvanced`. SwiftUI skips re-rendering rows whose props didn't change.
4. **`FileListSection` is a separate view** that takes plain values (not VMs). This isolates its body from unrelated parent re-renders.
5. **Default file list cap is 300 rows** (sorted by size). The `Show all` button raises the cap.
6. **Use `List` not `LazyVStack`.** On macOS, `List` is backed by `NSTableView` which is far faster for thousands of rows.
7. **NEVER add `.contextMenu` to row views.** Closure capture per row is expensive at scale. Put per-file actions in a detail panel or a hover-revealed menu, not on every row.
8. **`@Published` mutations in tight loops will freeze the UI.** Build the new value locally then assign once. See `selectAllSafe` / `selectAllInCategory`.
9. **Heavy work (sorting, dictionary build) goes through `Task.detached(priority: .userInitiated)`** and assigns the result on `MainActor` in a single statement.
10. **Scan progress events are deltas, not cumulative.** `ScanProgress` carries `deltaFiles` and `deltaSize`. The ViewModel accumulates them. Each parallel scan task yields its own delta — never compare or replace cumulative values across tasks.
11. **Throttle UI updates to ~4/sec** for high-frequency progress streams. See `ScanViewModel.startScan` for the pattern, and `CleaningViewModel.confirmCleaning` for the consumer-side version. Throttle in the CONSUMER, not the producer: a cheap `yield` still costs a main-actor hop plus a SwiftUI invalidation on the other end, and consumer-side throttling covers every producer at once. When you throttle, you must also flush the final buffered value — and `finish()` the stream then `await` the consumer rather than cancelling it, or the flush is dropped while the loop sits suspended on the stream.
12. **`ScanViewModel.State` is an enum with associated values** (`.completed(CompletedScan)`). Bundling result + sorted views + snapshots avoids a cascade of `@Published` notifications at end of scan.
13. **Disable list animations on category change.** `.animation(.none, value: selectedCategory)` — otherwise AppKit animates 1000 row insertions/deletions.
14. **Never run blocking syscalls directly inside `withTaskGroup`.** The directory walks (`scanDirectory` / `scanForLargeFiles`) are synchronous and never suspend, so each one pins a cooperative thread for its whole duration. The pool is capped near the core count, and `ScanViewModel` fans out one scanner per volume × ~22 targets — enough to exhaust it, at which point `await MainActor.run` hops queue behind a saturated executor and the UI freezes with a stalled-then-jumping counter. Blocking walks go through `BlockingScanExecutor` (dedicated queue + process-wide semaphore gate). The gate is static on purpose: a per-scanner limit would re-multiply by volume count.
15. **More I/O concurrency is not faster here.** Measured on an 11-core machine over 177k files: bounded 2/4/5/8 and unbounded all land at ~1.1–1.3s. The walk is I/O-bound on APFS metadata, not CPU-bound. For `DuplicateFinder`'s hashing, bound 16 actually *regressed* vs 8 (0.30s vs 0.17s). Bound the concurrency and spend the effort elsewhere.
16. **Memoize derived selection state lazily, not eagerly.** `selectedSize` / the grouped selection are invalidated (set to `nil`) on mutation and rebuilt on next read. Do NOT recompute eagerly inside `setSelectedIDs`: `toggleGroup` is called in loops (select-all across 50 groups = 100 mutations), and an O(selected) pass per mutation reintroduces the freeze at a different seam — it made `SelectionPerformanceTests.toggleGroupIsFast` fail at 1.04s against a 0.5s budget. Lazy invalidation makes a burst of N mutations pay for exactly one rebuild.
17. **The large-file sweep's skip list is MODE-DEPENDENT, and must stay that way.** Half its entries mean "another scan target covers this" (`Library/`, `Downloads/`, package-manager caches) and half mean "this is build noise" (`node_modules`, `.git`, `DerivedData`). The first group is only true on the boot volume: in `.externalVolume` mode `scanTargets` is empty and the sweep is the ONLY walk, so applying those entries made `/Volumes/T7/Library/` invisible with no warning — a silent false negative, which for a transparency-first app is worse than over-reporting. Noise entries apply everywhere.
18. **A relative-path skip list needs a canonical root, or it silently goes inert.** The URL APIs and `FileManager.enumerator` can disagree about the same directory: `temporaryDirectory` reports `/var/folders/…` and neither `resolvingSymlinksInPath()` nor `realpath(3)` rewrites it, yet the enumerator emits `/private/var/folders/…`. When the prefix strip fails, `relativePath` falls back to the absolute path, no relative entry can match, and the sweep quietly walks everything it was told to skip. Use `.canonicalPathKey` (resolved by the same machinery the enumerator uses) and treat a failed strip as "fall back to absolute matching", never as "skip nothing". This also makes tests non-vacuous: two mutation tests of the mode split passed spuriously until the strip worked, because the skip list was never actually applied.
19. **`Task.detached` does not inherit cancellation from the enclosing task.** It *can* be cancelled via its own handle (verified: `cancel()` on the handle does set `Task.isCancelled` inside it) — so hold the handle. `ScanViewModel.duplicateFinderTask` exists for this: without it, cancelling a scan left `DuplicateFinder` hashing gigabytes in the background. Adding `Task.isCancelled` checks to detached work is dead code unless something actually cancels it.

## Safety lessons

- **Deletions go to the Trash via `FileManager.trashItem`,** never permanent removal. We promised a "transparent and safe" tool — this is non-negotiable.
- **Destructive cleaning requires an explicit alert confirmation** (in `CleaningPreviewView`) when `dryRun` is OFF. There's also a special warning above 10 GB.
- **`CleaningEngine.neverDeletePrefixes`** blocks `/System`, `/usr`, `/bin`, `/sbin`. Add to it before adding new scanned roots.
- **Dry run is ON by default** for first-time users (`AppState.init`).
- **The classifier never returns `.appData` for installed apps' Application Support folders.** Only orphaned ones (apps no longer in `/Applications` or `~/Applications`) are flagged.

## TCC / Full Disk Access

The app needs Full Disk Access to scan `/private/var/log` and some system caches. Without it, the app still works but scans are partial — `MainView.welcomeView` shows a banner with a button to `FullDiskAccess.openSystemSettings()`.

The build script ad-hoc signs the app so TCC remembers the grant across rebuilds. Don't remove the `codesign --force --deep --sign -` step in `build-app.sh` — without it, the user has to re-grant FDA every time.

## Known limitations to remember

- The app uses a legacy `.icns` icon. macOS Tahoe applies an inset to legacy icons that we cannot override without using Xcode Icon Composer to generate a `.icon` asset. The icon will appear slightly smaller in the Dock than first-party Tahoe apps. This is documented and accepted.
- Time Machine snapshot deletion via `tmutil deletelocalsnapshots` may require admin privileges. The cleaning report adds a hint pointing the user to run `sudo tmutil deletelocalsnapshots <date>` in Terminal when this happens. We do NOT bundle a privileged helper.
- We are not signed with a Developer ID and not notarized. Distribution is local-only for now.

## Tests

- 267 tests in 43 suites. They MUST stay green. Run `swift test --no-parallel`
  before trusting a green result: suites run in parallel by default, and that
  extra scheduling slack has hidden at least one real failure
  (`selectionSummaryCountsGroupsAndFilesAcrossCategories` passed in parallel
  and failed serially — never the reverse). (If you change this count,
  run `swift test` and use the real number — a stale figure here is worse
  than none, since it's the guardrail everyone trusts.)
- Tests use Swift Testing (`@Test`, `@Suite`, `#expect`), not XCTest.
- Integration tests for `DiskScanner` and `CleaningEngine` use real temp directories under `FileManager.default.temporaryDirectory` — never touch the real home or the real Trash from tests.
- `ExclusionManager` tests pass a unique `userDefaultsSuiteName` per test to avoid cross-test pollution.
- Test names with `.app` extensions in paths trigger `.skipsPackageDescendants` in the FileManager enumerator. The scanner explicitly does NOT pass that option for category scans (only for the large-file scan). Don't change this without re-verifying the scanner integration tests.
- Suites to know about: `FileGrouper`, `BundleNames`, `FileDescriptions · iOS backups`, `CleaningViewModel` (toggleGroup), `CategoryClassifier` (orphan detection), `DiskScanner Integration` (including `progressStreamEmitsDeltas`).

## Categories (as of the file-category refactor)

Eleven categories, each with a classifier rule + grouper strategy:

| Category | Location(s) | Grouping |
|----------|-------------|----------|
| `.cache` | `~/Library/Caches` | by bundle id (`BundleNames.humanLabel`) |
| `.logs` | `~/Library/Logs`, `/private/var/log` | by bundle id; system logs in one bucket |
| `.tempFiles` | `/tmp`, `NSTemporaryDirectory()` | singleton |
| `.appData` | `~/Library/Application Support` (orphan only) | by bundle id |
| `.largeFiles` | anywhere in home > threshold | singleton |
| `.timeMachineSnapshots` | tmutil local snapshots | singleton |
| `.iosBackups` | `~/Library/Application Support/MobileSync/Backup` | by backup root folder (device) |
| `.xcodeJunk` | `~/Library/Developer/Xcode/{DerivedData,Archives,iOS DeviceSupport}`, `~/Library/Developer/CoreSimulator/Caches` | DerivedData grouped by project name (strip `-hash`), others by sub-root |
| `.devCaches` | `~/.npm`, `~/.yarn`, `~/.pnpm-store`, `~/.cache/{pip,huggingface,yarn}`, `~/.cargo/registry/cache`, `~/.rustup/toolchains`, `~/go/pkg/mod`, `~/Library/Caches/Homebrew` | by package manager |
| `.oldDownloads` | `~/Downloads` where mtime > 90 days ago | singleton |
| `.mailDownloads` | `~/Library/Mail Downloads`, `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | all collapsed into one row |

**Classifier ordering matters.** Rules run in this order: iOS Backups → Xcode Junk → Mail → Dev Caches → Caches → Logs → Temp → Orphan AppData → Old Downloads → Large Files. The Xcode Junk check comes BEFORE `.cache` because CoreSimulator caches are under `~/Library/Caches` and would otherwise be classified as generic caches.

**`.oldDownloads` is the only age-based category.** It requires `modificationDate` to be passed into `classify()`. The scanner already fetches it; don't remove the parameter.

## User-facing features (as of v0.1.0)

- **Inspector panel** (right side, toggled from toolbar). Click a row once to populate it with the group's size, file count, risk level, top-5 largest files, and Reveal in Finder / Quick Look / Copy Path actions. Never a per-row `.contextMenu` — that killed perf at scale.
- **Drag-and-drop** a folder anywhere on the window to scan just that folder via `ScanViewModel.startScan(folder:)`. The folder becomes the scanner's `homeDirectory` for that run.
- **Cancel scan** via the Cancel button in the sidebar. The scanner's static functions check `Task.isCancelled` every 200 iterations and bail out cleanly. `ScanViewModel.State` has a `.cancelling` intermediate state so the button shows "Cancelling…" until the task actually stops.
- **Auto-rescan after a real cleaning** — `MainView.onChange(of: cleaningVM.state)` triggers a fresh scan when `report.deletedCount > 0` and dry run is OFF.
- **Search** (⌘F / toolbar search field) filters the displayed groups by label. Resets when you switch category.
- **Keyboard shortcuts** in `MacSiftApp.commands`: ⌘R scan, ⌘. cancel, ⌘A select-all-safe, ⌘⇧A deselect all, Esc dismiss cleaning preview.
- **Scene storage** persists `selectedCategory` and `showAllFiles` across launches (NOT `isInspectorPresented` — see #69 in the history).
- **Reset all settings** in the Settings window wipes mode, dry-run, threshold, exclusions via an explicit alert.

## Release / distribution

- v0.1.0 is published at https://github.com/Lcharvol/MacSift/releases/tag/v0.1.0
- The release zip is named `MacSift.zip` (versionless) so deep links like
  `releases/latest/download/MacSift.zip` don't break with each new release.
  When cutting a new release, upload both `MacSift.zip` and `MacSift-X.Y.Z.zip`.
- Build process for a new release: bump version strings if needed, `swift test`,
  `./build-app.sh release`, `ditto -c -k --keepParent MacSift.app /tmp/MacSift.zip`,
  `git tag -a vX.Y.Z`, `gh release create`.
- The app is ad-hoc signed only (no paid Developer ID). First-launch requires
  right-click → Open. `build-app.sh` runs `codesign --force --deep --sign -` so
  TCC remembers Full Disk Access across rebuilds.
- Landing page lives in `docs/` on the `main` branch and is served by GitHub
  Pages at https://lcharvol.github.io/MacSift/. The `.nojekyll` file prevents
  Jekyll from processing the design specs that also live under `docs/`.

## Git workflow

- The user has a memory rule: never run `git init` or commit without explicit approval. They authorized commits for the current session.
- Commits should be conventional-ish (`feat:`, `fix:`, `perf:`, `polish:`, `chore:`) and end with the standard Co-Authored-By trailer.
- Remote: `https://github.com/Lcharvol/MacSift` (private, push allowed).

## When in doubt

- Prefer fewer files over more. We don't need a `Models/` subfolder per category.
- Prefer existing patterns over new abstractions. The codebase is small enough to read end-to-end.
- Profile before optimizing. Several earlier "optimizations" (the rotating gradient ring, the contextMenu per row) actually made things worse.
- Read the previous commit message before changing what it touched. The history explains the *why*.
