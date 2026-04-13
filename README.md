# MacSift

A transparent, trustworthy disk cleaning utility for macOS. Shows you exactly what's taking up space, groups it sensibly, and never permanently deletes anything — everything goes to the Trash so you can restore from Finder.

Built with Swift, SwiftUI, and the Liquid Glass APIs from macOS 26 (Tahoe).

## What it does

- **Scans** `~/Library/Caches`, `~/Library/Logs`, `~/Library/Application Support`, `/tmp`, `/private/var/log`, and your home directory for large files.
- **Detects** Time Machine local snapshots and iOS device backups.
- **Classifies** files into seven categories: Caches, Logs, Temporary Files, Unused App Data, Large Files, Time Machine Snapshots, iOS Backups.
- **Groups** files by owning app so thousands of `Library/Caches/com.apple.Safari/*` files show up as a single "Safari" row.
- **Orphans** — flags Application Support folders whose owning app is no longer installed.
- **Moves** selected items to the Trash via `FileManager.trashItem`. Never permanent deletion.

## Safety first

- **Dry Run mode is ON by default.** The first time you run MacSift, cleaning is simulated — nothing is touched.
- **Explicit confirmation** is required before any destructive delete. A warning appears above 10 GB.
- **System paths** (`/System`, `/usr`, `/bin`, `/sbin`) are hard-blocked.
- **Installed-app data** in Application Support is never flagged (only orphaned folders).
- **Everything goes to Trash.** Recover from Finder until you empty it.

## Build and run

```bash
# Compile + type-check
swift build

# Run the full test suite (~40 tests)
swift test

# Build the .app bundle and launch
./build-app.sh
open MacSift.app
```

The build script ad-hoc signs the bundle so macOS remembers your Full Disk Access grant across rebuilds. Without it you'd have to re-grant on every launch.

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 / Swift 6 toolchain
- Full Disk Access granted to `MacSift.app` (the app prompts you on first launch)

## Architecture

Strict MVVM. No Xcode project file — everything is driven by `Package.swift`.

```
MacSift/
├── App/             # @main, AppState
├── Models/          # FileCategory, ScannedFile, ScanResult, FileGroup (value types)
├── Services/        # DiskScanner, CategoryClassifier, FileGrouper, CleaningEngine,
│                      TimeMachineService, ExclusionManager
├── ViewModels/      # ScanViewModel, CleaningViewModel (@MainActor, @Published)
├── Views/           # SwiftUI views — kept dumb; take plain values where possible
└── Utilities/       # File size formatting, bundle name mapping, FDA check
```

See [`CLAUDE.md`](CLAUDE.md) for the full conventions, performance lessons, and safety rules.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘R` | Start/restart scan |
| `⌘.` | Cancel scan |
| `⌘A` | Select all safe items |
| `⌘⇧A` | Deselect all |
| `Esc` | Dismiss cleaning preview |

Drop any folder on the window to scan just that folder.

## Status

Personal project, not notarized, not distributed. Local-only for now.

## License

No explicit license — all rights reserved by the author.
