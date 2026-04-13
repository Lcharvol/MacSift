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
