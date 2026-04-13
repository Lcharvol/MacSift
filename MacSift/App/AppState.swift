import SwiftUI

/// App-wide observable state. We can't use @AppStorage here because that
/// property wrapper is designed for use directly on Views, not inside an
/// ObservableObject — it doesn't compose with @Published. The didSet pattern
/// below is the idiomatic alternative for an ObservableObject that mirrors
/// values to UserDefaults.
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

    /// Total number of scans run since install. Incremented once per
    /// completed scan in `ScanViewModel`.
    @Published var lifetimeScanCount: Int {
        didSet { UserDefaults.standard.set(lifetimeScanCount, forKey: "lifetimeScanCount") }
    }

    /// Total bytes moved to the Trash since install. Incremented by the
    /// freed size of each successful non-dry-run cleaning in `CleaningViewModel`.
    @Published var lifetimeCleanedBytes: Int64 {
        didSet { UserDefaults.standard.set(lifetimeCleanedBytes, forKey: "lifetimeCleanedBytes") }
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: "appMode") ?? Mode.simple.rawValue
        self.mode = Mode(rawValue: savedMode) ?? .simple
        self.isDryRun = UserDefaults.standard.object(forKey: "isDryRun") as? Bool ?? true
        self.largeFileThresholdMB = UserDefaults.standard.object(forKey: "largeFileThresholdMB") as? Int ?? 500
        self.lifetimeScanCount = UserDefaults.standard.integer(forKey: "lifetimeScanCount")
        self.lifetimeCleanedBytes = Int64(UserDefaults.standard.integer(forKey: "lifetimeCleanedBytes"))
    }

    var largeFileThresholdBytes: Int64 {
        Int64(largeFileThresholdMB) * 1024 * 1024
    }
}
