# MacSift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS cleaning tool that scans, categorizes, visualizes (treemap), and safely removes unnecessary system data with full transparency.

**Architecture:** Non-sandboxed SwiftUI app using MVVM. Services layer handles disk scanning (async/await + TaskGroup), category classification, and safe cleaning. Single monolithic target with no privileged helper.

**Tech Stack:** Swift, SwiftUI, macOS 14+, FileManager, Process (for tmutil), async/await, Canvas (treemap rendering)

---

## File Map

| File | Responsibility |
|------|---------------|
| `MacSift/App/MacSiftApp.swift` | App entry point, window configuration |
| `MacSift/App/AppState.swift` | Observable app-wide state: mode (simple/advanced), dry run toggle |
| `MacSift/Models/FileCategory.swift` | Enum with 7 categories, metadata (label, icon, color, riskLevel) |
| `MacSift/Models/ScannedFile.swift` | Struct: url, size, category, description, modificationDate, isDirectory |
| `MacSift/Models/ScanResult.swift` | Aggregated results: filesByCategory, totalSize, sizeByCategory, scanDuration |
| `MacSift/Utilities/FileSize+Formatting.swift` | Int64 extension for human-readable sizes |
| `MacSift/Utilities/FileDescriptions.swift` | Static descriptions per category/path pattern |
| `MacSift/Utilities/Permissions.swift` | Full Disk Access check + System Settings deep link |
| `MacSift/Services/CategoryClassifier.swift` | Path-prefix classification logic |
| `MacSift/Services/ExclusionManager.swift` | UserDefaults-backed folder whitelist |
| `MacSift/Services/DiskScanner.swift` | Async recursive scanner with TaskGroup, AsyncStream progress |
| `MacSift/Services/TimeMachineService.swift` | tmutil wrapper: list/delete local snapshots |
| `MacSift/Services/CleaningEngine.swift` | Safe deletion with dry run, never-delete list, error handling |
| `MacSift/ViewModels/ScanViewModel.swift` | Orchestrates scan, publishes results + progress |
| `MacSift/ViewModels/CleaningViewModel.swift` | Orchestrates cleaning flow: selection, preview, execution |
| `MacSift/Views/MainView.swift` | NavigationSplitView: sidebar + content |
| `MacSift/Views/ScanProgressView.swift` | Real-time scan progress display |
| `MacSift/Views/CategoryListView.swift` | Sidebar category list with icons and sizes |
| `MacSift/Views/TreemapView.swift` | Custom Canvas squarified treemap |
| `MacSift/Views/FileDetailView.swift` | Detail view for selected file/folder |
| `MacSift/Views/CleaningPreviewView.swift` | Modal: pre-delete summary, risk levels, confirmation |
| `MacSift/Views/SettingsView.swift` | Exclusions, mode toggle, dry run, large file threshold |
| `MacSiftTests/FileSizeFormattingTests.swift` | Unit tests for size formatting |
| `MacSiftTests/FileDescriptionsTests.swift` | Unit tests for human descriptions |
| `MacSiftTests/CategoryClassifierTests.swift` | Unit tests for classification logic |
| `MacSiftTests/ExclusionManagerTests.swift` | Unit tests for exclusion rules |
| `MacSiftTests/ScanResultTests.swift` | Unit tests for result aggregation |
| `MacSiftTests/DiskScannerIntegrationTests.swift` | Integration tests with temp directory |
| `MacSiftTests/CleaningEngineIntegrationTests.swift` | Integration tests for deletion + dry run |
| `MacSiftTests/TimeMachineServiceTests.swift` | Tests with mocked tmutil output |

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `MacSift.xcodeproj` (via `xcodebuild` / Swift Package)
- Create: `MacSift/App/MacSiftApp.swift`
- Create: `MacSift/App/AppState.swift`

- [ ] **Step 1: Create the Xcode project**

Use Xcode CLI to create a new macOS app project. From `/Users/lucascharvolin/Projects/MacSift`:

```bash
cd /Users/lucascharvolin/Projects/MacSift
mkdir -p MacSift/App MacSift/Models MacSift/Services MacSift/ViewModels MacSift/Views MacSift/Utilities
mkdir -p MacSiftTests
mkdir -p MacSiftUITests
```

Create `Package.swift` at the project root:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacSift", targets: ["MacSift"])
    ],
    targets: [
        .executableTarget(
            name: "MacSift",
            path: "MacSift"
        ),
        .testTarget(
            name: "MacSiftTests",
            dependencies: ["MacSift"],
            path: "MacSiftTests"
        )
    ]
)
```

- [ ] **Step 2: Create the app entry point**

Create `MacSift/App/MacSiftApp.swift`:

```swift
import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
    }
}

struct ContentView: View {
    var body: some View {
        Text("MacSift")
            .font(.largeTitle)
    }
}
```

- [ ] **Step 3: Create AppState**

Create `MacSift/App/AppState.swift`:

```swift
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Mode: String, CaseIterable {
        case simple
        case advanced
    }

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "appMode") }
    }

    @Published var isDryRun: Bool {
        didSet { UserDefaults.standard.set(isDryRun, forKey: "isDryRun") }
    }

    @Published var largeFileThresholdMB: Int {
        didSet { UserDefaults.standard.set(largeFileThresholdMB, forKey: "largeFileThresholdMB") }
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: "appMode") ?? Mode.simple.rawValue
        self.mode = Mode(rawValue: savedMode) ?? .simple
        self.isDryRun = UserDefaults.standard.object(forKey: "isDryRun") as? Bool ?? true
        self.largeFileThresholdMB = UserDefaults.standard.object(forKey: "largeFileThresholdMB") as? Int ?? 500
    }

    var largeFileThresholdBytes: Int64 {
        Int64(largeFileThresholdMB) * 1024 * 1024
    }
}
```

- [ ] **Step 4: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 5: Initialize git and commit**

```bash
cd /Users/lucascharvolin/Projects/MacSift
git init
cat > .gitignore << 'GITIGNORE'
.DS_Store
.build/
.swiftpm/
*.xcodeproj
xcuserdata/
DerivedData/
GITIGNORE
git add .
git commit -m "feat: initial project setup with SwiftUI app skeleton and AppState"
```

---

## Task 2: Data Models — FileCategory, ScannedFile, ScanResult

**Files:**
- Create: `MacSift/Models/FileCategory.swift`
- Create: `MacSift/Models/ScannedFile.swift`
- Create: `MacSift/Models/ScanResult.swift`

- [ ] **Step 1: Create FileCategory**

Create `MacSift/Models/FileCategory.swift`:

```swift
import SwiftUI

enum RiskLevel: String, CaseIterable, Sendable {
    case safe
    case moderate
    case risky

    var color: Color {
        switch self {
        case .safe: .green
        case .moderate: .orange
        case .risky: .red
        }
    }

    var label: String {
        switch self {
        case .safe: "Safe to delete"
        case .moderate: "Review recommended"
        case .risky: "Use caution"
        }
    }
}

enum FileCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case cache
    case logs
    case tempFiles
    case appData
    case largeFiles
    case timeMachineSnapshots
    case iosBackups

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cache: "Caches"
        case .logs: "Logs"
        case .tempFiles: "Temporary Files"
        case .appData: "Unused App Data"
        case .largeFiles: "Large Files"
        case .timeMachineSnapshots: "Time Machine Snapshots"
        case .iosBackups: "iOS Backups"
        }
    }

    var iconName: String {
        switch self {
        case .cache: "folder.badge.gearshape"
        case .logs: "doc.text"
        case .tempFiles: "clock.arrow.circlepath"
        case .appData: "app.dashed"
        case .largeFiles: "externaldrive"
        case .timeMachineSnapshots: "timemachine"
        case .iosBackups: "iphone"
        }
    }

    var riskLevel: RiskLevel {
        switch self {
        case .cache, .logs, .tempFiles: .safe
        case .appData, .timeMachineSnapshots: .moderate
        case .largeFiles, .iosBackups: .risky
        }
    }

    var displayColor: Color {
        switch self {
        case .cache: .blue
        case .logs: .gray
        case .tempFiles: .cyan
        case .appData: .purple
        case .largeFiles: .orange
        case .timeMachineSnapshots: .green
        case .iosBackups: .pink
        }
    }
}
```

- [ ] **Step 2: Create ScannedFile**

Create `MacSift/Models/ScannedFile.swift`:

```swift
import Foundation

struct ScannedFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64
    let category: FileCategory
    let description: String
    let modificationDate: Date
    let isDirectory: Bool

    init(
        url: URL,
        size: Int64,
        category: FileCategory,
        description: String,
        modificationDate: Date,
        isDirectory: Bool
    ) {
        self.id = UUID()
        self.url = url
        self.size = size
        self.category = category
        self.description = description
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }

    var name: String {
        url.lastPathComponent
    }

    var path: String {
        url.path(percentEncoded: false)
    }
}
```

- [ ] **Step 3: Create ScanResult**

Create `MacSift/Models/ScanResult.swift`:

```swift
import Foundation

struct ScanResult: Sendable {
    let filesByCategory: [FileCategory: [ScannedFile]]
    let scanDuration: TimeInterval

    var totalSize: Int64 {
        filesByCategory.values.flatMap { $0 }.reduce(0) { $0 + $1.size }
    }

    var sizeByCategory: [FileCategory: Int64] {
        filesByCategory.mapValues { files in
            files.reduce(0) { $0 + $1.size }
        }
    }

    var totalFileCount: Int {
        filesByCategory.values.reduce(0) { $0 + $1.count }
    }

    static let empty = ScanResult(filesByCategory: [:], scanDuration: 0)
}
```

- [ ] **Step 4: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Models/
git commit -m "feat: add data models — FileCategory, ScannedFile, ScanResult"
```

---

## Task 3: Utilities — FileSize Formatting, FileDescriptions, Permissions

**Files:**
- Create: `MacSift/Utilities/FileSize+Formatting.swift`
- Create: `MacSift/Utilities/FileDescriptions.swift`
- Create: `MacSift/Utilities/Permissions.swift`
- Create: `MacSiftTests/FileSizeFormattingTests.swift`
- Create: `MacSiftTests/FileDescriptionsTests.swift`

- [ ] **Step 1: Write failing tests for FileSize formatting**

Create `MacSiftTests/FileSizeFormattingTests.swift`:

```swift
import Testing
@testable import MacSift

@Suite("FileSize Formatting")
struct FileSizeFormattingTests {
    @Test func formatsBytes() {
        #expect(Int64(0).formattedFileSize == "0 B")
        #expect(Int64(512).formattedFileSize == "512 B")
        #expect(Int64(1023).formattedFileSize == "1,023 B")
    }

    @Test func formatsKilobytes() {
        #expect(Int64(1024).formattedFileSize == "1.0 KB")
        #expect(Int64(1536).formattedFileSize == "1.5 KB")
        #expect(Int64(10240).formattedFileSize == "10.0 KB")
    }

    @Test func formatsMegabytes() {
        #expect(Int64(1_048_576).formattedFileSize == "1.0 MB")
        #expect(Int64(5_242_880).formattedFileSize == "5.0 MB")
    }

    @Test func formatsGigabytes() {
        #expect(Int64(1_073_741_824).formattedFileSize == "1.0 GB")
        #expect(Int64(2_684_354_560).formattedFileSize == "2.5 GB")
    }

    @Test func formatsTerabytes() {
        #expect(Int64(1_099_511_627_776).formattedFileSize == "1.0 TB")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter FileSizeFormattingTests 2>&1
```

Expected: Compilation error — `formattedFileSize` not defined.

- [ ] **Step 3: Implement FileSize+Formatting**

Create `MacSift/Utilities/FileSize+Formatting.swift`:

```swift
import Foundation

extension Int64 {
    var formattedFileSize: String {
        let units: [(String, Int64)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1024),
        ]

        for (label, threshold) in units {
            if self >= threshold {
                let value = Double(self) / Double(threshold)
                return String(format: "%.1f %@", value, label)
            }
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: self)) ?? "\(self)"
        return "\(formatted) B"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter FileSizeFormattingTests 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Write failing tests for FileDescriptions**

Create `MacSiftTests/FileDescriptionsTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("FileDescriptions")
struct FileDescriptionsTests {
    @Test func describesCacheFiles() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Caches/com.apple.Safari")
        let desc = FileDescriptions.describe(url: url, category: .cache)
        #expect(desc.contains("Safari"))
    }

    @Test func describesLogFiles() {
        let url = URL(filePath: "/private/var/log/system.log")
        let desc = FileDescriptions.describe(url: url, category: .logs)
        #expect(desc.contains("System log"))
    }

    @Test func describesIOSBackup() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appending(path: "Library/Application Support/MobileSync/Backup/abc123")
        let desc = FileDescriptions.describe(url: url, category: .iosBackups)
        #expect(desc.contains("iOS"))
    }

    @Test func fallsBackToGenericDescription() {
        let url = URL(filePath: "/tmp/random_file.dat")
        let desc = FileDescriptions.describe(url: url, category: .tempFiles)
        #expect(!desc.isEmpty)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter FileDescriptionsTests 2>&1
```

Expected: Compilation error — `FileDescriptions` not defined.

- [ ] **Step 7: Implement FileDescriptions**

Create `MacSift/Utilities/FileDescriptions.swift`:

```swift
import Foundation

enum FileDescriptions {
    static func describe(url: URL, category: FileCategory) -> String {
        let name = url.lastPathComponent
        let path = url.path(percentEncoded: false).lowercased()

        switch category {
        case .cache:
            return describeCacheFile(name: name, path: path)
        case .logs:
            return describeLogFile(name: name, path: path)
        case .tempFiles:
            return "Temporary file: \(name)"
        case .appData:
            return "Unused app data: \(name)"
        case .largeFiles:
            return "Large file: \(name)"
        case .timeMachineSnapshots:
            return "Time Machine local snapshot"
        case .iosBackups:
            return "iOS device backup: \(name)"
        }
    }

    private static func describeCacheFile(name: String, path: String) -> String {
        let knownApps: [(pattern: String, label: String)] = [
            ("safari", "Safari"),
            ("chrome", "Google Chrome"),
            ("firefox", "Firefox"),
            ("slack", "Slack"),
            ("spotify", "Spotify"),
            ("discord", "Discord"),
            ("xcode", "Xcode"),
            ("figma", "Figma"),
        ]

        for app in knownApps {
            if path.contains(app.pattern) || name.lowercased().contains(app.pattern) {
                return "\(app.label) cache"
            }
        }
        return "Application cache: \(name)"
    }

    private static func describeLogFile(name: String, path: String) -> String {
        if path.contains("/private/var/log") {
            return "System log: \(name)"
        }
        return "Application log: \(name)"
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter FileDescriptionsTests 2>&1
```

Expected: All tests pass.

- [ ] **Step 9: Implement Permissions utility**

Create `MacSift/Utilities/Permissions.swift`:

```swift
import Foundation
import AppKit

enum FullDiskAccess {
    static func check() -> Bool {
        let testPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        return FileManager.default.isReadableFile(atPath: testPath)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 10: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 11: Commit**

```bash
git add MacSift/Utilities/ MacSiftTests/FileSizeFormattingTests.swift MacSiftTests/FileDescriptionsTests.swift
git commit -m "feat: add utilities — file size formatting, descriptions, permissions check"
```

---

## Task 4: CategoryClassifier Service

**Files:**
- Create: `MacSift/Services/CategoryClassifier.swift`
- Create: `MacSiftTests/CategoryClassifierTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MacSiftTests/CategoryClassifierTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("CategoryClassifier")
struct CategoryClassifierTests {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let classifier = CategoryClassifier()

    @Test func classifiesCacheFiles() {
        let url = home.appending(path: "Library/Caches/com.apple.Safari/something.db")
        #expect(classifier.classify(url: url, size: 1000) == .cache)
    }

    @Test func classifiesUserLogs() {
        let url = home.appending(path: "Library/Logs/DiagnosticReports/crash.log")
        #expect(classifier.classify(url: url, size: 1000) == .logs)
    }

    @Test func classifiesSystemLogs() {
        let url = URL(filePath: "/private/var/log/system.log")
        #expect(classifier.classify(url: url, size: 1000) == .logs)
    }

    @Test func classifiesTempFiles() {
        let url = URL(filePath: "/tmp/some_temp_file.dat")
        #expect(classifier.classify(url: url, size: 1000) == .tempFiles)
    }

    @Test func classifiesIOSBackups() {
        let url = home.appending(path: "Library/Application Support/MobileSync/Backup/abc123/Info.plist")
        #expect(classifier.classify(url: url, size: 1000) == .iosBackups)
    }

    @Test func classifiesLargeFiles() {
        let url = home.appending(path: "Documents/huge_video.mov")
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1) == .largeFiles)
    }

    @Test func doesNotClassifySmallFilesAsLarge() {
        let url = home.appending(path: "Documents/small_file.txt")
        #expect(classifier.classify(url: url, size: 1000) == nil)
    }

    @Test func respectsCustomLargeFileThreshold() {
        let customClassifier = CategoryClassifier(largeFileThresholdBytes: 100)
        let url = home.appending(path: "Documents/medium_file.txt")
        #expect(customClassifier.classify(url: url, size: 101) == .largeFiles)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter CategoryClassifierTests 2>&1
```

Expected: Compilation error — `CategoryClassifier` not defined.

- [ ] **Step 3: Implement CategoryClassifier**

Create `MacSift/Services/CategoryClassifier.swift`:

```swift
import Foundation

struct CategoryClassifier: Sendable {
    let largeFileThresholdBytes: Int64

    init(largeFileThresholdBytes: Int64 = 500 * 1024 * 1024) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
    }

    func classify(url: URL, size: Int64) -> FileCategory? {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

        // iOS Backups (check before general appData)
        if path.contains("MobileSync/Backup") {
            return .iosBackups
        }

        // Caches
        if path.hasPrefix("\(home)Library/Caches") {
            return .cache
        }

        // Logs
        if path.hasPrefix("\(home)Library/Logs") || path.hasPrefix("/private/var/log") {
            return .logs
        }

        // Temp files
        if path.hasPrefix("/tmp") || path.hasPrefix(NSTemporaryDirectory()) {
            return .tempFiles
        }

        // Large files (anywhere in home)
        if path.hasPrefix(home) && size > largeFileThresholdBytes {
            return .largeFiles
        }

        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter CategoryClassifierTests 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Services/CategoryClassifier.swift MacSiftTests/CategoryClassifierTests.swift
git commit -m "feat: add CategoryClassifier with path-prefix classification logic"
```

---

## Task 5: ExclusionManager Service

**Files:**
- Create: `MacSift/Services/ExclusionManager.swift`
- Create: `MacSiftTests/ExclusionManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MacSiftTests/ExclusionManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("ExclusionManager")
struct ExclusionManagerTests {
    @Test func startsEmpty() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        #expect(manager.excludedPaths.isEmpty)
    }

    @Test func addsExclusion() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        #expect(manager.excludedPaths.count == 1)
        #expect(manager.isExcluded(url))
    }

    @Test func removesExclusion() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        manager.removeExclusion(url)
        #expect(manager.excludedPaths.isEmpty)
        #expect(!manager.isExcluded(url))
    }

    @Test func excludesChildPaths() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let parent = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(parent)
        let child = URL(filePath: "/Users/test/Documents/keep/subdir/file.txt")
        #expect(manager.isExcluded(child))
    }

    @Test func doesNotExcludeUnrelatedPaths() {
        let manager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let url = URL(filePath: "/Users/test/Documents/keep")
        manager.addExclusion(url)
        let other = URL(filePath: "/Users/test/Downloads/file.txt")
        #expect(!manager.isExcluded(other))
    }

    @Test func persistsExclusions() {
        let suite = "test.\(UUID().uuidString)"
        let url = URL(filePath: "/Users/test/Documents/keep")

        let manager1 = ExclusionManager(userDefaultsSuiteName: suite)
        manager1.addExclusion(url)

        let manager2 = ExclusionManager(userDefaultsSuiteName: suite)
        #expect(manager2.isExcluded(url))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter ExclusionManagerTests 2>&1
```

Expected: Compilation error — `ExclusionManager` not defined.

- [ ] **Step 3: Implement ExclusionManager**

Create `MacSift/Services/ExclusionManager.swift`:

```swift
import Foundation

@MainActor
final class ExclusionManager: ObservableObject {
    @Published private(set) var excludedPaths: [URL]
    private let defaults: UserDefaults

    init(userDefaultsSuiteName: String? = nil) {
        if let suite = userDefaultsSuiteName {
            self.defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            self.defaults = .standard
        }

        let saved = defaults.stringArray(forKey: "excludedPaths") ?? []
        self.excludedPaths = saved.map { URL(filePath: $0) }
    }

    func addExclusion(_ url: URL) {
        guard !excludedPaths.contains(url) else { return }
        excludedPaths.append(url)
        persist()
    }

    func removeExclusion(_ url: URL) {
        excludedPaths.removeAll { $0 == url }
        persist()
    }

    func isExcluded(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return excludedPaths.contains { excludedURL in
            let excludedPath = excludedURL.path(percentEncoded: false)
            return path == excludedPath || path.hasPrefix(excludedPath + "/")
        }
    }

    private func persist() {
        let paths = excludedPaths.map { $0.path(percentEncoded: false) }
        defaults.set(paths, forKey: "excludedPaths")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter ExclusionManagerTests 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Services/ExclusionManager.swift MacSiftTests/ExclusionManagerTests.swift
git commit -m "feat: add ExclusionManager with UserDefaults persistence"
```

---

## Task 6: ScanResult Tests

**Files:**
- Create: `MacSiftTests/ScanResultTests.swift`

- [ ] **Step 1: Write tests for ScanResult**

Create `MacSiftTests/ScanResultTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("ScanResult")
struct ScanResultTests {
    @Test func computesTotalSize() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 200, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/c"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.5)
        #expect(result.totalSize == 600)
    }

    @Test func computesSizeByCategory() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.0)
        #expect(result.sizeByCategory[.cache] == 100)
        #expect(result.sizeByCategory[.logs] == 300)
    }

    @Test func computesTotalFileCount() {
        let files: [FileCategory: [ScannedFile]] = [
            .cache: [
                ScannedFile(url: URL(filePath: "/tmp/a"), size: 100, category: .cache, description: "", modificationDate: .now, isDirectory: false),
            ],
            .logs: [
                ScannedFile(url: URL(filePath: "/tmp/b"), size: 200, category: .logs, description: "", modificationDate: .now, isDirectory: false),
                ScannedFile(url: URL(filePath: "/tmp/c"), size: 300, category: .logs, description: "", modificationDate: .now, isDirectory: false),
            ],
        ]
        let result = ScanResult(filesByCategory: files, scanDuration: 1.0)
        #expect(result.totalFileCount == 3)
    }

    @Test func emptyResultIsZero() {
        let result = ScanResult.empty
        #expect(result.totalSize == 0)
        #expect(result.totalFileCount == 0)
        #expect(result.sizeByCategory.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter ScanResultTests 2>&1
```

Expected: All tests pass (models already implemented).

- [ ] **Step 3: Commit**

```bash
git add MacSiftTests/ScanResultTests.swift
git commit -m "test: add ScanResult unit tests"
```

---

## Task 7: DiskScanner Service

**Files:**
- Create: `MacSift/Services/DiskScanner.swift`
- Create: `MacSiftTests/DiskScannerIntegrationTests.swift`

- [ ] **Step 1: Write failing integration tests**

Create `MacSiftTests/DiskScannerIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("DiskScanner Integration")
struct DiskScannerIntegrationTests {
    private func createTempStructure() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftTest-\(UUID().uuidString)")
        let fm = FileManager.default

        let cacheDir = tempDir.appending(path: "Library/Caches/com.test.app")
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 1024).write(to: cacheDir.appending(path: "cache.db"))

        let logDir = tempDir.appending(path: "Library/Logs")
        try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 2048).write(to: logDir.appending(path: "app.log"))

        return tempDir
    }

    @Test func scansAndCategorizesFiles() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let exclusionManager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        let result = await scanner.scan()

        #expect(result.totalFileCount >= 2)
        #expect(result.filesByCategory[.cache]?.isEmpty == false)
        #expect(result.filesByCategory[.logs]?.isEmpty == false)
    }

    @Test func respectsExclusions() async throws {
        let tempDir = try createTempStructure()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exclusionManager = ExclusionManager(userDefaultsSuiteName: "test.\(UUID().uuidString)")
        await MainActor.run {
            exclusionManager.addExclusion(tempDir.appending(path: "Library/Caches"))
        }

        let classifier = CategoryClassifier(largeFileThresholdBytes: 500 * 1024 * 1024)
        let scanner = DiskScanner(
            classifier: classifier,
            exclusionManager: exclusionManager,
            homeDirectory: tempDir
        )

        let result = await scanner.scan()

        #expect(result.filesByCategory[.cache] == nil || result.filesByCategory[.cache]?.isEmpty == true)
        #expect(result.filesByCategory[.logs]?.isEmpty == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter DiskScannerIntegration 2>&1
```

Expected: Compilation error — `DiskScanner` not defined.

- [ ] **Step 3: Implement DiskScanner**

Create `MacSift/Services/DiskScanner.swift`:

```swift
import Foundation

struct ScanProgress: Sendable {
    let filesFound: Int
    let currentSize: Int64
    let currentPath: String
    let category: FileCategory?
}

actor DiskScanner {
    private let classifier: CategoryClassifier
    private let exclusionManager: ExclusionManager
    private let homeDirectory: URL
    private let maxDepth: Int

    private var progressContinuation: AsyncStream<ScanProgress>.Continuation?

    init(
        classifier: CategoryClassifier,
        exclusionManager: ExclusionManager,
        homeDirectory: URL? = nil,
        maxDepth: Int = 20
    ) {
        self.classifier = classifier
        self.exclusionManager = exclusionManager
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.maxDepth = maxDepth
    }

    var progressStream: AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }

    func scan() async -> ScanResult {
        let startTime = Date()

        let scanTargets: [(URL, FileCategory?)] = [
            (homeDirectory.appending(path: "Library/Caches"), .cache),
            (homeDirectory.appending(path: "Library/Logs"), .logs),
            (homeDirectory.appending(path: "Library/Application Support"), nil),
            (URL(filePath: "/private/var/log"), .logs),
            (URL(filePath: "/tmp"), .tempFiles),
        ]

        var allFiles: [FileCategory: [ScannedFile]] = [:]

        await withTaskGroup(of: [ScannedFile].self) { group in
            for (url, hintCategory) in scanTargets {
                group.addTask { [self] in
                    await self.scanDirectory(url, hintCategory: hintCategory)
                }
            }

            // Large file scan across home
            group.addTask { [self] in
                await self.scanForLargeFiles(in: self.homeDirectory)
            }

            for await files in group {
                for file in files {
                    allFiles[file.category, default: []].append(file)
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        progressContinuation?.finish()

        return ScanResult(filesByCategory: allFiles, scanDuration: duration)
    }

    private func scanDirectory(_ directory: URL, hintCategory: FileCategory?) async -> [ScannedFile] {
        let fm = FileManager.default
        let isExcluded = await MainActor.run { exclusionManager.isExcluded(directory) }
        guard !isExcluded else { return [] }
        guard fm.isReadableFile(atPath: directory.path(percentEncoded: false)) else { return [] }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var files: [ScannedFile] = []
        var depth = 0

        for case let fileURL as URL in enumerator {
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let isExcludedFile = await MainActor.run { exclusionManager.isExcluded(fileURL) }
            if isExcludedFile {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            let isDir = values.isDirectory ?? false
            if isDir {
                depth = enumerator.level
                continue
            }

            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate ?? .distantPast

            let category: FileCategory
            if let hint = hintCategory {
                category = hint
            } else if let classified = classifier.classify(url: fileURL, size: size) {
                category = classified
            } else {
                continue
            }

            let description = FileDescriptions.describe(url: fileURL, category: category)

            let scannedFile = ScannedFile(
                url: fileURL,
                size: size,
                category: category,
                description: description,
                modificationDate: modDate,
                isDirectory: false
            )

            files.append(scannedFile)

            progressContinuation?.yield(ScanProgress(
                filesFound: files.count,
                currentSize: files.reduce(0) { $0 + $1.size },
                currentPath: fileURL.lastPathComponent,
                category: category
            ))
        }

        return files
    }

    private func scanForLargeFiles(in directory: URL) async -> [ScannedFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let skipPrefixes = ["Library/Caches", "Library/Logs", "Library/Application Support"]
        let homePath = directory.path(percentEncoded: false)
        var files: [ScannedFile] = []

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path(percentEncoded: false)
            let relativePath = String(filePath.dropFirst(homePath.count))

            if skipPrefixes.contains(where: { relativePath.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }

            let isExcludedFile = await MainActor.run { exclusionManager.isExcluded(fileURL) }
            if isExcludedFile {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }

            if values.isSymbolicLink == true || values.isDirectory == true { continue }

            let size = Int64(values.fileSize ?? 0)
            guard size > classifier.largeFileThresholdBytes else { continue }

            let modDate = values.contentModificationDate ?? .distantPast
            let description = FileDescriptions.describe(url: fileURL, category: .largeFiles)

            files.append(ScannedFile(
                url: fileURL,
                size: size,
                category: .largeFiles,
                description: description,
                modificationDate: modDate,
                isDirectory: false
            ))
        }

        return files
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter DiskScannerIntegration 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Services/DiskScanner.swift MacSiftTests/DiskScannerIntegrationTests.swift
git commit -m "feat: add DiskScanner with parallel async scanning and exclusion support"
```

---

## Task 8: TimeMachineService

**Files:**
- Create: `MacSift/Services/TimeMachineService.swift`
- Create: `MacSiftTests/TimeMachineServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `MacSiftTests/TimeMachineServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("TimeMachineService")
struct TimeMachineServiceTests {
    @Test func parsesSnapshotOutput() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-04-01-120000.local
        com.apple.TimeMachine.2026-04-10-080000.local
        """

        let snapshots = TimeMachineService.parseSnapshots(from: output)

        #expect(snapshots.count == 2)
        #expect(snapshots[0].identifier == "com.apple.TimeMachine.2026-04-01-120000.local")
        #expect(snapshots[0].dateString == "2026-04-01-120000")
        #expect(snapshots[1].identifier == "com.apple.TimeMachine.2026-04-10-080000.local")
    }

    @Test func parsesEmptyOutput() {
        let output = "Snapshots for disk /:\n"
        let snapshots = TimeMachineService.parseSnapshots(from: output)
        #expect(snapshots.isEmpty)
    }

    @Test func handlesNoSnapshotsMessage() {
        let output = ""
        let snapshots = TimeMachineService.parseSnapshots(from: output)
        #expect(snapshots.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter TimeMachineServiceTests 2>&1
```

Expected: Compilation error — `TimeMachineService` not defined.

- [ ] **Step 3: Implement TimeMachineService**

Create `MacSift/Services/TimeMachineService.swift`:

```swift
import Foundation

struct TMSnapshot: Identifiable, Sendable {
    let id = UUID()
    let identifier: String
    let dateString: String

    var displayDate: String {
        let parts = dateString.split(separator: "-")
        guard parts.count >= 4 else { return dateString }
        return "\(parts[0])-\(parts[1])-\(parts[2]) \(parts[3].prefix(2)):\(parts[3].dropFirst(2).prefix(2))"
    }
}

enum TimeMachineService {
    static func parseSnapshots(from output: String) -> [TMSnapshot] {
        output
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
            .compactMap { line -> TMSnapshot? in
                let identifier = line.trimmingCharacters(in: .whitespaces)
                let prefix = "com.apple.TimeMachine."
                let suffix = ".local"
                guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else { return nil }
                let dateString = String(identifier.dropFirst(prefix.count).dropLast(suffix.count))
                return TMSnapshot(identifier: identifier, dateString: dateString)
            }
    }

    static func listSnapshots() async throws -> [TMSnapshot] {
        let output = try await runTmutil(arguments: ["listlocalsnapshots", "/"])
        return parseSnapshots(from: output)
    }

    static func deleteSnapshot(dateString: String) async throws {
        _ = try await runTmutil(arguments: ["deletelocalsnapshots", dateString])
    }

    private static func runTmutil(arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/tmutil")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: TMError.commandFailed(output))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum TMError: Error, LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let output): "tmutil failed: \(output)"
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter TimeMachineServiceTests 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Services/TimeMachineService.swift MacSiftTests/TimeMachineServiceTests.swift
git commit -m "feat: add TimeMachineService with tmutil snapshot parsing"
```

---

## Task 9: CleaningEngine Service

**Files:**
- Create: `MacSift/Services/CleaningEngine.swift`
- Create: `MacSiftTests/CleaningEngineIntegrationTests.swift`

- [ ] **Step 1: Write failing integration tests**

Create `MacSiftTests/CleaningEngineIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import MacSift

@Suite("CleaningEngine Integration")
struct CleaningEngineIntegrationTests {
    private func createTempFile(in dir: URL, name: String, size: Int) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: name)
        try Data(repeating: 0xFF, count: size).write(to: fileURL)
        return fileURL
    }

    private func makeScannedFile(url: URL, size: Int64) -> ScannedFile {
        ScannedFile(
            url: url,
            size: size,
            category: .cache,
            description: "Test file",
            modificationDate: .now,
            isDirectory: false
        )
    }

    @Test func deletesFilesSuccessfully() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = try createTempFile(in: tempDir, name: "delete_me.dat", size: 1024)
        let file = makeScannedFile(url: fileURL, size: 1024)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        #expect(report.deletedCount == 1)
        #expect(report.freedSize == 1024)
        #expect(report.failedFiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test func dryRunDoesNotDeleteFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = try createTempFile(in: tempDir, name: "keep_me.dat", size: 2048)
        let file = makeScannedFile(url: fileURL, size: 2048)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: true)

        #expect(report.deletedCount == 1)
        #expect(report.freedSize == 2048)
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test func handlesAlreadyDeletedFiles() async throws {
        let fileURL = URL(filePath: "/tmp/MacSiftCleanTest-nonexistent-\(UUID().uuidString).dat")
        let file = makeScannedFile(url: fileURL, size: 500)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        // File was already gone — treated as success (silent skip)
        #expect(report.failedFiles.isEmpty)
    }

    @Test func handlesPermissionErrors() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "MacSiftCleanTest-\(UUID().uuidString)")
        defer {
            // Restore permissions before cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: tempDir)
        }

        let fileURL = try createTempFile(in: tempDir, name: "locked.dat", size: 512)
        // Make parent dir read-only so file can't be deleted
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: tempDir.path(percentEncoded: false))

        let file = makeScannedFile(url: fileURL, size: 512)

        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)

        #expect(report.failedFiles.count == 1)
        #expect(report.deletedCount == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter CleaningEngineIntegration 2>&1
```

Expected: Compilation error — `CleaningEngine` not defined.

- [ ] **Step 3: Implement CleaningEngine**

Create `MacSift/Services/CleaningEngine.swift`:

```swift
import Foundation

struct CleaningReport: Sendable {
    let deletedCount: Int
    let freedSize: Int64
    let failedFiles: [(ScannedFile, String)]
    let totalProcessed: Int

    var successRate: Double {
        guard totalProcessed > 0 else { return 1.0 }
        return Double(deletedCount) / Double(totalProcessed)
    }
}

struct CleaningProgress: Sendable {
    let processed: Int
    let total: Int
    let currentFile: String
    let freedSoFar: Int64
}

actor CleaningEngine {
    private static let neverDeletePrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
    ]

    private var progressContinuation: AsyncStream<CleaningProgress>.Continuation?

    var progressStream: AsyncStream<CleaningProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation
        }
    }

    func clean(files: [ScannedFile], dryRun: Bool) async -> CleaningReport {
        var deletedCount = 0
        var freedSize: Int64 = 0
        var failedFiles: [(ScannedFile, String)] = []
        let fm = FileManager.default

        for (index, file) in files.enumerated() {
            let path = file.url.path(percentEncoded: false)

            // Safety: never delete system paths
            if Self.neverDeletePrefixes.contains(where: { path.hasPrefix($0) }) {
                failedFiles.append((file, "System file — deletion blocked for safety"))
                continue
            }

            progressContinuation?.yield(CleaningProgress(
                processed: index + 1,
                total: files.count,
                currentFile: file.name,
                freedSoFar: freedSize
            ))

            if dryRun {
                deletedCount += 1
                freedSize += file.size
                continue
            }

            // If file is already gone, skip silently
            guard fm.fileExists(atPath: path) else { continue }

            do {
                try fm.removeItem(at: file.url)
                deletedCount += 1
                freedSize += file.size
            } catch {
                failedFiles.append((file, error.localizedDescription))
            }
        }

        progressContinuation?.finish()

        return CleaningReport(
            deletedCount: deletedCount,
            freedSize: freedSize,
            failedFiles: failedFiles,
            totalProcessed: files.count
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test --filter CleaningEngineIntegration 2>&1
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Services/CleaningEngine.swift MacSiftTests/CleaningEngineIntegrationTests.swift
git commit -m "feat: add CleaningEngine with dry run, safety checks, and error handling"
```

---

## Task 10: ScanViewModel

**Files:**
- Create: `MacSift/ViewModels/ScanViewModel.swift`

- [ ] **Step 1: Implement ScanViewModel**

Create `MacSift/ViewModels/ScanViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case completed
    }

    @Published var state: State = .idle
    @Published var result: ScanResult = .empty
    @Published var progress: ScanProgress?
    @Published var tmSnapshots: [TMSnapshot] = []
    @Published var hasFullDiskAccess: Bool = false

    private let exclusionManager: ExclusionManager
    private let appState: AppState

    init(exclusionManager: ExclusionManager, appState: AppState) {
        self.exclusionManager = exclusionManager
        self.appState = appState
        self.hasFullDiskAccess = FullDiskAccess.check()
    }

    func startScan() async {
        state = .scanning
        progress = nil

        let classifier = CategoryClassifier(largeFileThresholdBytes: appState.largeFileThresholdBytes)
        let scanner = DiskScanner(classifier: classifier, exclusionManager: exclusionManager)

        // Start progress monitoring
        Task {
            for await scanProgress in await scanner.progressStream {
                self.progress = scanProgress
            }
        }

        // Run scan
        let scanResult = await scanner.scan()

        // Fetch TM snapshots separately
        let snapshots = (try? await TimeMachineService.listSnapshots()) ?? []

        self.result = scanResult
        self.tmSnapshots = snapshots
        self.state = .completed
    }

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.check()
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MacSift/ViewModels/ScanViewModel.swift
git commit -m "feat: add ScanViewModel orchestrating scan with progress tracking"
```

---

## Task 11: CleaningViewModel

**Files:**
- Create: `MacSift/ViewModels/CleaningViewModel.swift`

- [ ] **Step 1: Implement CleaningViewModel**

Create `MacSift/ViewModels/CleaningViewModel.swift`:

```swift
import SwiftUI

@MainActor
final class CleaningViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case previewing
        case cleaning
        case completed
    }

    @Published var state: State = .idle
    @Published var selectedFiles: Set<ScannedFile> = []
    @Published var report: CleaningReport?
    @Published var cleaningProgress: CleaningProgress?
    @Published var showPreview: Bool = false

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var selectedSize: Int64 {
        selectedFiles.reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        selectedFiles.count
    }

    var selectedByCategory: [FileCategory: [ScannedFile]] {
        Dictionary(grouping: Array(selectedFiles), by: \.category)
    }

    func toggleFile(_ file: ScannedFile) {
        if selectedFiles.contains(file) {
            selectedFiles.remove(file)
        } else {
            selectedFiles.insert(file)
        }
    }

    func selectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        for file in files {
            selectedFiles.insert(file)
        }
    }

    func deselectAllInCategory(_ category: FileCategory, files: [ScannedFile]) {
        for file in files {
            selectedFiles.remove(file)
        }
    }

    func selectAllSafe(from result: ScanResult) {
        for (category, files) in result.filesByCategory {
            if category.riskLevel == .safe {
                for file in files {
                    selectedFiles.insert(file)
                }
            }
        }
    }

    func showCleaningPreview() {
        guard !selectedFiles.isEmpty else { return }
        showPreview = true
        state = .previewing
    }

    func cancelPreview() {
        showPreview = false
        state = .idle
    }

    func confirmCleaning() async {
        state = .cleaning
        showPreview = false

        let engine = CleaningEngine()

        Task {
            for await progress in await engine.progressStream {
                self.cleaningProgress = progress
            }
        }

        let cleaningReport = await engine.clean(
            files: Array(selectedFiles),
            dryRun: appState.isDryRun
        )

        self.report = cleaningReport
        self.selectedFiles.removeAll()
        self.state = .completed
    }

    func reset() {
        state = .idle
        report = nil
        cleaningProgress = nil
    }
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MacSift/ViewModels/CleaningViewModel.swift
git commit -m "feat: add CleaningViewModel with selection, preview, and cleaning flow"
```

---

## Task 12: MainView + Sidebar (CategoryListView)

**Files:**
- Create: `MacSift/Views/MainView.swift`
- Create: `MacSift/Views/CategoryListView.swift`
- Modify: `MacSift/App/MacSiftApp.swift`

- [ ] **Step 1: Create CategoryListView**

Create `MacSift/Views/CategoryListView.swift`:

```swift
import SwiftUI

struct CategoryListView: View {
    let sizeByCategory: [FileCategory: Int64]
    @Binding var selectedCategory: FileCategory?

    var body: some View {
        List(selection: $selectedCategory) {
            ForEach(FileCategory.allCases) { category in
                let size = sizeByCategory[category] ?? 0

                Label {
                    HStack {
                        Text(category.label)
                        Spacer()
                        if size > 0 {
                            Text(size.formattedFileSize)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: category.iconName)
                        .foregroundStyle(category.displayColor)
                }
                .tag(category)
            }
        }
    }
}
```

- [ ] **Step 2: Create MainView**

Create `MacSift/Views/MainView.swift`:

```swift
import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var scanVM: ScanViewModel
    @StateObject private var cleaningVM: CleaningViewModel
    @State private var selectedCategory: FileCategory?

    init(exclusionManager: ExclusionManager, appState: AppState) {
        _scanVM = StateObject(wrappedValue: ScanViewModel(exclusionManager: exclusionManager, appState: appState))
        _cleaningVM = StateObject(wrappedValue: CleaningViewModel(appState: appState))
    }

    var body: some View {
        NavigationSplitView {
            VStack {
                Button {
                    Task { await scanVM.startScan() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.top, 8)
                .disabled(scanVM.state == .scanning)

                CategoryListView(
                    sizeByCategory: scanVM.result.sizeByCategory,
                    selectedCategory: $selectedCategory
                )

                Divider()

                HStack {
                    Picker("Mode", selection: $appState.mode) {
                        Text("Simple").tag(AppState.Mode.simple)
                        Text("Advanced").tag(AppState.Mode.advanced)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            detailContent
        }
        .sheet(isPresented: $cleaningVM.showPreview) {
            CleaningPreviewView(cleaningVM: cleaningVM, appState: appState)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch scanVM.state {
        case .idle:
            welcomeView
        case .scanning:
            ScanProgressView(progress: scanVM.progress)
        case .completed:
            resultsView
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("MacSift")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Scan your disk to find unnecessary files")
                .foregroundStyle(.secondary)

            if !scanVM.hasFullDiskAccess {
                fullDiskAccessBanner
            }

            Button {
                Task { await scanVM.startScan() }
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Full Disk Access not granted. Some files may not be scanned.")
                .font(.callout)
            Spacer()
            Button("Open Settings") {
                FullDiskAccess.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 40)
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Treemap placeholder — implemented in Task 14
            TreemapView(
                result: scanVM.result,
                selectedCategory: $selectedCategory
            )
            .frame(height: 250)

            Divider()

            // File list
            fileListView

            // Bottom bar
            bottomBar
        }
    }

    private var fileListView: some View {
        let files: [ScannedFile] = {
            if let category = selectedCategory {
                return scanVM.result.filesByCategory[category] ?? []
            }
            return scanVM.result.filesByCategory.values.flatMap { $0 }.sorted { $0.size > $1.size }
        }()

        return List(files) { file in
            FileDetailView(
                file: file,
                isSelected: cleaningVM.selectedFiles.contains(file),
                isAdvanced: appState.mode == .advanced,
                onToggle: { cleaningVM.toggleFile(file) }
            )
        }
    }

    private var bottomBar: some View {
        HStack {
            if cleaningVM.selectedCount > 0 {
                Text("\(cleaningVM.selectedCount) files selected (\(cleaningVM.selectedSize.formattedFileSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.mode == .simple {
                Button("Select All Safe") {
                    cleaningVM.selectAllSafe(from: scanVM.result)
                }
                .buttonStyle(.bordered)
            }

            Button("Clean Selected") {
                cleaningVM.showCleaningPreview()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(cleaningVM.selectedFiles.isEmpty)
        }
        .padding()
        .background(.bar)
    }
}
```

- [ ] **Step 3: Update MacSiftApp to use MainView**

Replace the `ContentView` in `MacSift/App/MacSiftApp.swift`:

```swift
import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var exclusionManager = ExclusionManager()

    var body: some Scene {
        WindowGroup {
            MainView(exclusionManager: exclusionManager, appState: appState)
                .environmentObject(appState)
                .environmentObject(exclusionManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
    }
}
```

- [ ] **Step 4: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build fails — `ScanProgressView`, `TreemapView`, `FileDetailView`, `CleaningPreviewView` not yet defined. We'll stub them next.

- [ ] **Step 5: Commit**

```bash
git add MacSift/Views/MainView.swift MacSift/Views/CategoryListView.swift MacSift/App/MacSiftApp.swift
git commit -m "feat: add MainView with sidebar navigation and CategoryListView"
```

---

## Task 13: ScanProgressView + FileDetailView + CleaningPreviewView + SettingsView

**Files:**
- Create: `MacSift/Views/ScanProgressView.swift`
- Create: `MacSift/Views/FileDetailView.swift`
- Create: `MacSift/Views/CleaningPreviewView.swift`
- Create: `MacSift/Views/SettingsView.swift`

- [ ] **Step 1: Create ScanProgressView**

Create `MacSift/Views/ScanProgressView.swift`:

```swift
import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning...")
                .font(.title2)
                .fontWeight(.semibold)

            if let progress {
                VStack(spacing: 8) {
                    Text("\(progress.filesFound) files found")
                        .font(.headline)

                    Text(progress.currentSize.formattedFileSize)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)

                    if let category = progress.category {
                        Label(category.label, systemImage: category.iconName)
                            .foregroundStyle(category.displayColor)
                    }

                    Text(progress.currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Create FileDetailView**

Create `MacSift/Views/FileDetailView.swift`:

```swift
import SwiftUI

struct FileDetailView: View {
    let file: ScannedFile
    let isSelected: Bool
    let isAdvanced: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Image(systemName: file.category.iconName)
                .foregroundStyle(file.category.displayColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(file.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if isAdvanced {
                    Text(file.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(file.size.formattedFileSize)
                    .fontWeight(.medium)
                    .font(.callout)

                if isAdvanced {
                    Text(file.modificationDate, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isAdvanced {
                Circle()
                    .fill(file.category.riskLevel.color)
                    .frame(width: 8, height: 8)
                    .help(file.category.riskLevel.label)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Create CleaningPreviewView**

Create `MacSift/Views/CleaningPreviewView.swift`:

```swift
import SwiftUI

struct CleaningPreviewView: View {
    @ObservedObject var cleaningVM: CleaningViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cleaning Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") {
                    cleaningVM.cancelPreview()
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            if cleaningVM.state == .cleaning {
                cleaningProgressView
            } else if let report = cleaningVM.report {
                cleaningReportView(report)
            } else {
                previewContent
            }
        }
        .frame(width: 550, height: 450)
    }

    private var previewContent: some View {
        VStack(spacing: 16) {
            // Summary by category
            List {
                ForEach(FileCategory.allCases) { category in
                    let files = cleaningVM.selectedByCategory[category] ?? []
                    if !files.isEmpty {
                        let categorySize = files.reduce(0 as Int64) { $0 + $1.size }
                        HStack {
                            Image(systemName: category.iconName)
                                .foregroundStyle(category.displayColor)
                            Text(category.label)
                            Spacer()
                            Circle()
                                .fill(category.riskLevel.color)
                                .frame(width: 8, height: 8)
                            Text("\(files.count) files")
                                .foregroundStyle(.secondary)
                            Text(categorySize.formattedFileSize)
                                .fontWeight(.medium)
                        }
                    }
                }
            }

            // Dry run toggle
            Toggle("Dry Run (simulate only)", isOn: $appState.isDryRun)
                .padding(.horizontal)

            if appState.isDryRun {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Dry run mode: no files will actually be deleted.")
                        .font(.callout)
                }
                .padding(.horizontal)
            }

            // Confirm button
            Button {
                Task { await cleaningVM.confirmCleaning() }
            } label: {
                Text("Delete \(cleaningVM.selectedCount) files (\(cleaningVM.selectedSize.formattedFileSize))")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.isDryRun ? .blue : .red)
            .controlSize(.large)
            .padding()
        }
    }

    private var cleaningProgressView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView(
                value: Double(cleaningVM.cleaningProgress?.processed ?? 0),
                total: Double(cleaningVM.cleaningProgress?.total ?? 1)
            )
            .padding(.horizontal)

            if let progress = cleaningVM.cleaningProgress {
                Text("Processing \(progress.processed)/\(progress.total)")
                    .font(.headline)
                Text(progress.currentFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Freed: \(progress.freedSoFar.formattedFileSize)")
                    .font(.callout)
            }

            Spacer()
        }
    }

    private func cleaningReportView(_ report: CleaningReport) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: report.failedFiles.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(report.failedFiles.isEmpty ? .green : .orange)

            Text(appState.isDryRun ? "Dry Run Complete" : "Cleaning Complete")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 4) {
                Text("\(report.deletedCount) files \(appState.isDryRun ? "would be" : "") deleted")
                Text("\(report.freedSize.formattedFileSize) \(appState.isDryRun ? "would be" : "") freed")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            if !report.failedFiles.isEmpty {
                Divider()
                Text("\(report.failedFiles.count) files could not be deleted:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                List(report.failedFiles.prefix(10), id: \.0.id) { file, reason in
                    VStack(alignment: .leading) {
                        Text(file.name)
                            .fontWeight(.medium)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxHeight: 150)
            }

            Spacer()

            Button("Done") {
                cleaningVM.reset()
                cleaningVM.showPreview = false
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}
```

- [ ] **Step 4: Create SettingsView**

Create `MacSift/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var exclusionManager: ExclusionManager

    var body: some View {
        Form {
            Section("General") {
                Picker("Mode", selection: $appState.mode) {
                    Text("Simple").tag(AppState.Mode.simple)
                    Text("Advanced").tag(AppState.Mode.advanced)
                }

                Toggle("Dry Run (simulate deletions)", isOn: $appState.isDryRun)

                HStack {
                    Text("Large file threshold")
                    Spacer()
                    TextField("MB", value: $appState.largeFileThresholdMB, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("MB")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Excluded Folders") {
                ForEach(exclusionManager.excludedPaths, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            exclusionManager.removeExclusion(url)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK, let url = panel.url {
                        exclusionManager.addExclusion(url)
                    }
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Full Disk Access")
                    Spacer()
                    if FullDiskAccess.check() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            FullDiskAccess.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }
}
```

- [ ] **Step 5: Verify it builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build fails — `TreemapView` not yet created. Will be implemented in next task.

- [ ] **Step 6: Commit**

```bash
git add MacSift/Views/ScanProgressView.swift MacSift/Views/FileDetailView.swift MacSift/Views/CleaningPreviewView.swift MacSift/Views/SettingsView.swift
git commit -m "feat: add ScanProgressView, FileDetailView, CleaningPreviewView, SettingsView"
```

---

## Task 14: TreemapView

**Files:**
- Create: `MacSift/Views/TreemapView.swift`

- [ ] **Step 1: Implement the squarified treemap algorithm and Canvas view**

Create `MacSift/Views/TreemapView.swift`:

```swift
import SwiftUI

struct TreemapItem: Identifiable {
    let id: String
    let label: String
    let size: Int64
    let color: Color
    let category: FileCategory
}

struct TreemapRect {
    let item: TreemapItem
    let rect: CGRect
}

struct TreemapView: View {
    let result: ScanResult
    @Binding var selectedCategory: FileCategory?
    @State private var hoveredItem: String?
    @State private var tooltipPosition: CGPoint = .zero

    private var items: [TreemapItem] {
        result.sizeByCategory
            .filter { $0.value > 0 }
            .map { category, size in
                TreemapItem(
                    id: category.rawValue,
                    label: category.label,
                    size: size,
                    color: category.displayColor,
                    category: category
                )
            }
            .sorted { $0.size > $1.size }
    }

    var body: some View {
        GeometryReader { geometry in
            let rects = squarify(items: items, in: CGRect(origin: .zero, size: geometry.size))

            ZStack {
                Canvas { context, _ in
                    for treemapRect in rects {
                        let insetRect = treemapRect.rect.insetBy(dx: 1.5, dy: 1.5)
                        let path = RoundedRectangle(cornerRadius: 4)
                            .path(in: insetRect)

                        let isHovered = hoveredItem == treemapRect.item.id
                        let opacity: Double = isHovered ? 0.9 : 0.7

                        context.fill(path, with: .color(treemapRect.item.color.opacity(opacity)))

                        // Draw label if rect is large enough
                        if insetRect.width > 60 && insetRect.height > 30 {
                            let text = Text(treemapRect.item.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            context.draw(
                                context.resolve(text),
                                at: CGPoint(x: insetRect.midX, y: insetRect.midY - 8)
                            )

                            let sizeText = Text(treemapRect.item.size.formattedFileSize)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                            context.draw(
                                context.resolve(sizeText),
                                at: CGPoint(x: insetRect.midX, y: insetRect.midY + 8)
                            )
                        }
                    }
                }

                // Invisible overlay for hit-testing
                ForEach(rects, id: \.item.id) { treemapRect in
                    Rectangle()
                        .fill(.clear)
                        .frame(width: treemapRect.rect.width, height: treemapRect.rect.height)
                        .position(
                            x: treemapRect.rect.midX,
                            y: treemapRect.rect.midY
                        )
                        .onHover { isHovered in
                            hoveredItem = isHovered ? treemapRect.item.id : nil
                        }
                        .onTapGesture {
                            selectedCategory = treemapRect.item.category
                        }
                        .help("\(treemapRect.item.label): \(treemapRect.item.size.formattedFileSize)")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // Squarified treemap algorithm
    private func squarify(items: [TreemapItem], in bounds: CGRect) -> [TreemapRect] {
        guard !items.isEmpty else { return [] }
        guard bounds.width > 0 && bounds.height > 0 else { return [] }

        let totalSize = items.reduce(0 as Int64) { $0 + $1.size }
        guard totalSize > 0 else { return [] }

        var results: [TreemapRect] = []
        var remaining = items
        var currentBounds = bounds

        while !remaining.isEmpty {
            let isWide = currentBounds.width >= currentBounds.height
            let sideLength = isWide ? currentBounds.height : currentBounds.width

            let remainingTotal = remaining.reduce(0 as Int64) { $0 + $1.size }
            var row: [TreemapItem] = []
            var rowSize: Int64 = 0

            // Greedily add items to current row while aspect ratio improves
            for item in remaining {
                let newRow = row + [item]
                let newRowSize = rowSize + item.size

                if row.isEmpty || worstAspectRatio(newRow, rowSize: newRowSize, totalSize: remainingTotal, sideLength: sideLength, totalArea: currentBounds.width * currentBounds.height) <=
                    worstAspectRatio(row, rowSize: rowSize, totalSize: remainingTotal, sideLength: sideLength, totalArea: currentBounds.width * currentBounds.height) {
                    row = newRow
                    rowSize = newRowSize
                } else {
                    break
                }
            }

            // Layout the row
            let rowFraction = Double(rowSize) / Double(remainingTotal)

            if isWide {
                let rowWidth = currentBounds.width * rowFraction
                var y = currentBounds.minY

                for item in row {
                    let itemFraction = Double(item.size) / Double(rowSize)
                    let itemHeight = currentBounds.height * itemFraction
                    results.append(TreemapRect(
                        item: item,
                        rect: CGRect(x: currentBounds.minX, y: y, width: rowWidth, height: itemHeight)
                    ))
                    y += itemHeight
                }

                currentBounds = CGRect(
                    x: currentBounds.minX + rowWidth,
                    y: currentBounds.minY,
                    width: currentBounds.width - rowWidth,
                    height: currentBounds.height
                )
            } else {
                let rowHeight = currentBounds.height * rowFraction
                var x = currentBounds.minX

                for item in row {
                    let itemFraction = Double(item.size) / Double(rowSize)
                    let itemWidth = currentBounds.width * itemFraction
                    results.append(TreemapRect(
                        item: item,
                        rect: CGRect(x: x, y: currentBounds.minY, width: itemWidth, height: rowHeight)
                    ))
                    x += itemWidth
                }

                currentBounds = CGRect(
                    x: currentBounds.minX,
                    y: currentBounds.minY + rowHeight,
                    width: currentBounds.width,
                    height: currentBounds.height - rowHeight
                )
            }

            remaining = Array(remaining.dropFirst(row.count))
        }

        return results
    }

    private func worstAspectRatio(_ row: [TreemapItem], rowSize: Int64, totalSize: Int64, sideLength: CGFloat, totalArea: CGFloat) -> CGFloat {
        guard !row.isEmpty, rowSize > 0, totalSize > 0 else { return CGFloat.greatestFiniteMagnitude }

        let rowArea = totalArea * Double(rowSize) / Double(totalSize)
        let rowLength = rowArea / Double(sideLength)

        var worst: CGFloat = 0
        for item in row {
            let itemArea = totalArea * Double(item.size) / Double(totalSize)
            let itemLength = itemArea / rowLength

            let aspect = max(itemLength / rowLength, rowLength / itemLength)
            worst = max(worst, aspect)
        }

        return worst
    }
}
```

- [ ] **Step 2: Verify the full app builds**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds — all views are now defined.

- [ ] **Step 3: Commit**

```bash
git add MacSift/Views/TreemapView.swift
git commit -m "feat: add TreemapView with squarified treemap algorithm and Canvas rendering"
```

---

## Task 15: Wire Up Settings + Final Integration

**Files:**
- Modify: `MacSift/Views/MainView.swift`
- Modify: `MacSift/App/MacSiftApp.swift`

- [ ] **Step 1: Add Settings window to MacSiftApp**

Update `MacSift/App/MacSiftApp.swift` to add a Settings scene:

```swift
import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var exclusionManager = ExclusionManager()

    var body: some Scene {
        WindowGroup {
            MainView(exclusionManager: exclusionManager, appState: appState)
                .environmentObject(appState)
                .environmentObject(exclusionManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView(exclusionManager: exclusionManager)
                .environmentObject(appState)
        }
    }
}
```

- [ ] **Step 2: Verify it builds and run**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift build
```

Expected: Build succeeds.

- [ ] **Step 3: Run all tests**

```bash
cd /Users/lucascharvolin/Projects/MacSift
swift test 2>&1
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add MacSift/App/MacSiftApp.swift MacSift/Views/MainView.swift
git commit -m "feat: wire up Settings window and finalize app integration"
```

---

## Task 16: Generate Xcode Project (optional, for running the app)

**Files:**
- No new files — generates `.xcodeproj` from `Package.swift`

- [ ] **Step 1: Open in Xcode to run**

Since this is a SwiftUI macOS app, you need Xcode to actually run it with a window:

```bash
cd /Users/lucascharvolin/Projects/MacSift
open Package.swift
```

This opens the project in Xcode where you can hit Run (Cmd+R) to launch the app.

- [ ] **Step 2: Verify the app launches**

In Xcode: select the `MacSift` scheme, target "My Mac", press Cmd+R. The app should open with the welcome screen showing the MacSift logo and "Start Scan" button.

- [ ] **Step 3: Test the scan flow**

Click "Start Scan" and verify:
- Progress view appears during scanning
- Categories populate in the sidebar with sizes
- Treemap renders with colored rectangles
- File list shows detected files with descriptions
- Simple/Advanced mode toggle changes the detail level

- [ ] **Step 4: Test the cleaning flow**

Select some files, click "Clean Selected":
- Preview sheet shows summary with risk levels
- Dry run toggle works (enabled by default)
- Confirmation button shows count and size
- After confirming dry run, report shows what would be deleted

- [ ] **Step 5: Final commit**

```bash
cd /Users/lucascharvolin/Projects/MacSift
git add -A
git commit -m "chore: finalize MacSift MVP — all features implemented"
```
