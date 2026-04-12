# MacSift — Design Specification

## Overview

MacSift is a macOS cleaning tool that helps users identify and remove unnecessary system data (caches, logs, temporary files, unused app data, large hidden files, Time Machine snapshots, iOS backups). The key differentiator is transparency and control — no black-box cleaning.

**Target audience:** Both technical users (granular control) and general users (simple one-click), served by a simple/advanced mode toggle.

**Distribution:** Non-sandboxed, DMG download. Requires Full Disk Access for complete scanning.

**Tech stack:** Swift, SwiftUI, MVVM, async/await. Single-target monolithic app.

---

## 1. Project Structure

```
MacSift/
├── MacSift.xcodeproj
├── MacSift/
│   ├── App/
│   │   ├── MacSiftApp.swift              # Entry point
│   │   └── AppState.swift                # App-wide state (simple/advanced mode)
│   ├── Models/
│   │   ├── ScannedFile.swift             # Individual file (path, size, category, description)
│   │   ├── FileCategory.swift            # Enum: 7 categories with metadata
│   │   └── ScanResult.swift              # Aggregated scan results
│   ├── Services/
│   │   ├── DiskScanner.swift             # Async recursive scanning with TaskGroup
│   │   ├── CategoryClassifier.swift      # Path-based category assignment
│   │   ├── CleaningEngine.swift          # Safe deletion, dry run, error handling
│   │   ├── TimeMachineService.swift      # tmutil interaction for local snapshots
│   │   └── ExclusionManager.swift        # Whitelist of excluded folders
│   ├── ViewModels/
│   │   ├── ScanViewModel.swift           # Orchestrates scanning, exposes results
│   │   └── CleaningViewModel.swift       # Orchestrates cleaning, preview, confirmation
│   ├── Views/
│   │   ├── MainView.swift                # Sidebar + content layout
│   │   ├── ScanProgressView.swift        # Real-time progress during scan
│   │   ├── CategoryListView.swift        # Category list with sizes
│   │   ├── TreemapView.swift             # Custom Canvas treemap visualization
│   │   ├── FileDetailView.swift          # Selected file/folder details
│   │   ├── CleaningPreviewView.swift     # Pre-deletion preview + confirmation
│   │   └── SettingsView.swift            # Exclusions, mode toggle, dry run
│   └── Utilities/
│       ├── FileSize+Formatting.swift     # Size formatting extensions (KB, MB, GB)
│       ├── FileDescriptions.swift        # Human-readable descriptions per category/path
│       └── Permissions.swift             # Full Disk Access verification
├── MacSiftTests/
│   ├── CategoryClassifierTests.swift
│   ├── ExclusionManagerTests.swift
│   ├── FileSizeFormattingTests.swift
│   ├── FileDescriptionsTests.swift
│   ├── ScanResultTests.swift
│   ├── DiskScannerIntegrationTests.swift
│   ├── CleaningEngineIntegrationTests.swift
│   └── TimeMachineServiceTests.swift
└── MacSiftUITests/
    └── NavigationUITests.swift
```

---

## 2. Data Model

### ScannedFile
Represents a detected file or directory:
- `url: URL` — full path
- `size: Int64` — size in bytes
- `category: FileCategory` — assigned category
- `description: String` — human-readable explanation ("Safari cache", "Old iPhone 12 backup")
- `modificationDate: Date` — last modified
- `isDirectory: Bool`

### FileCategory
Enum with 7 values, each carrying metadata:

| Category | Scanned Paths | SF Symbol | Risk Level |
|----------|--------------|-----------|------------|
| `.cache` | `~/Library/Caches` | `folder.badge.gearshape` | `.safe` |
| `.logs` | `~/Library/Logs`, `/private/var/log` | `doc.text` | `.safe` |
| `.tempFiles` | `/tmp`, `NSTemporaryDirectory()` | `clock.arrow.circlepath` | `.safe` |
| `.appData` | `~/Library/Application Support` (orphaned) | `app.dashed` | `.moderate` |
| `.largeFiles` | Home directory, files > 500MB (configurable) | `externaldrive` | `.risky` |
| `.timeMachineSnapshots` | Local TM snapshots via `tmutil` | `timemachine` | `.moderate` |
| `.iosBackups` | `~/Library/Application Support/MobileSync/Backup` | `iphone` | `.risky` |

Risk levels: `.safe` (green), `.moderate` (orange), `.risky` (red).

### ScanResult
Aggregation of scan results:
- `filesByCategory: [FileCategory: [ScannedFile]]`
- `totalSize: Int64`
- `sizeByCategory: [FileCategory: Int64]`
- `scanDuration: TimeInterval`

---

## 3. Disk Scanning Engine

### DiskScanner

**Scanned paths:**
- `~/Library/Caches`
- `~/Library/Logs`
- `~/Library/Application Support` (orphaned app detection + iOS backups)
- `/private/var/log` (requires Full Disk Access)
- `/tmp`, `NSTemporaryDirectory()`
- Home directory for large files (> configurable threshold, default 500MB)

**Mechanism:**
- Uses `FileManager.enumerator(at:includingPropertiesForKeys:)` with keys `[.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]` to minimize syscalls
- `async/await` with `TaskGroup` — one task per root path, scans run in parallel
- Publishes real-time progress via `AsyncStream<ScanProgress>` (files found, current size, current path)
- `CategoryClassifier` called for each file — simple path-prefix logic
- Orphaned app detection: compares folders in `Application Support` against installed apps in `/Applications`

### TimeMachineService
- Executes `tmutil listlocalsnapshots /` via `Process`
- Parses output to extract snapshots with dates
- Cleaning: `tmutil deletelocalsnapshots <date>`

### Performance
- Scan of `~/Library`: a few seconds typically
- Large file scan across home directory is slowest — launched last so other categories display results first

---

## 4. Cleaning Engine & Safety

### Dry Run Mode
- Global toggle in settings, enabled by default on first launch
- In dry run, the entire process runs normally except `FileManager.removeItem` is never called
- Logs show exactly what *would* be deleted with sizes

### Deletion Flow
1. User selects files or entire categories
2. `CleaningPreviewView` displays summary: file count, total size, per-category detail, risk levels
3. Explicit confirmation required (button: "Delete X files (Y GB)")
4. Sequential file-by-file deletion with real-time progress
5. Final report: deleted, failed (permissions), total size freed

### Never-Delete List
- Anything outside known scanned paths
- `~/Library/Application Support` entries for still-installed apps
- System files (`/System`, `/usr`, `/bin`, `/sbin`)
- The MacSift app itself

### Permission Error Handling
- If a file can't be deleted: log error, continue with remaining files
- End-of-clean report lists failed files with explanation ("Permission denied — grant Full Disk Access in System Settings")

### ExclusionManager
- Users can add folders to a whitelist persisted via `UserDefaults`
- Excluded folders are ignored during both scanning and cleaning
- Some default exclusion suggestions (e.g., `MobileSync` if user wants to keep backups)

### Crash Safety
- No batch atomic deletes — each file removed individually
- If app crashes mid-clean, only already-processed files are deleted, no state corruption

---

## 5. UI & Navigation

### Layout
Sidebar + Content area using `NavigationSplitView` (native macOS style).

### Sidebar
- "Scan" button at top
- Category list with SF Symbol icon, label, and detected size
- Each category clickable to filter main view
- Bottom: Settings access, simple/advanced mode toggle

### Simple vs Advanced Mode
- **Simple:** Sidebar shows categories with sizes + "Clean All Safe Items" button. Treemap shows categories. Selection by whole category.
- **Advanced:** Full detail — individual files per category, interactive treemap with drill-down to file level, granular file-by-file selection, risk levels displayed.

### Content Area — 3 States
1. **Pre-scan:** Welcome screen with "Start Scan" button. Full Disk Access check with link to System Settings if missing.
2. **Scanning:** Real-time progress (files found, current size, categories filling in progressively).
3. **Results:** Treemap at top (clickable for drill-down), detailed list below. Each file shows: name, size, human description, modification date, selection checkbox.

### Treemap
- Custom rendering via SwiftUI `Canvas`
- Squarified treemap algorithm for readable rectangles
- Colors per category (consistent with sidebar)
- Click = drill-down into category/folder
- Tooltip on hover with name + size

### CleaningPreviewView
- Modal sheet triggered by "Clean Selected" button
- Selected files summarized by category
- Risk level indicators (green/orange/red)
- "Dry run" checkbox
- Confirmation button showing total size

---

## 6. Error Handling & Permissions

### Full Disk Access Check
- On launch, app tests access by attempting to read `/Library/Application Support/com.apple.TCC/TCC.db`
- If denied: persistent banner at top of app with explanation + "Open System Settings" button linking to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`
- Scan works partially without FDA (home directory accessible, `/private/var/log` and some system caches not) — shows accessible results with warning about incomplete scan

### Scan Errors
- Permission denied on a directory: skip, continue, count inaccessible directories
- Symbolic links: ignored to prevent infinite loops
- Deep directories: configurable depth limit (default 20 levels)

### Cleaning Errors
- File locked / in use: skip + log
- Permission denied: skip + FDA suggestion
- File disappeared between scan and clean: silent skip
- Final report always shown with failure details

---

## 7. Testing Strategy

### Unit Tests
- `CategoryClassifier` — correct category assignment for known paths
- `ExclusionManager` — add/remove rules, verify excluded paths are filtered
- `FileSize+Formatting` — correct formatting (bytes, KB, MB, GB, TB)
- `FileDescriptions` — correct human descriptions per category and known paths
- `ScanResult` — correct size aggregation by category

### Integration Tests
- `DiskScanner` — scan a pre-populated temp directory, verify all files found and categorized
- `CleaningEngine` — actual deletion in temp directory, dry run verification (files intact), permission error handling (read-only file)
- `TimeMachineService` — parse mocked `tmutil` output (no real snapshots in tests)

### UI Tests (light)
- Sidebar navigation -> category -> files
- Full flow: scan -> selection -> preview -> confirmation
- Simple/advanced mode toggle

### Not Tested
- Pixel-perfect treemap rendering (too fragile)
- Real filesystem calls outside test temp directories
