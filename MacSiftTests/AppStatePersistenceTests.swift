import Testing
import Foundation
@testable import MacSift

/// Verifies that AppState reads from and writes to UserDefaults on every
/// relevant @Published property. The didSet pattern is easy to break
/// silently (forget to update one key when adding a new field), so these
/// tests serve as tripwires.
///
/// NOTE: AppState uses `UserDefaults.standard` so we can't isolate per
/// test without a bigger refactor. We work around this by saving the
/// keys at test start, resetting to known values, and restoring in a
/// teardown-style defer. The suite is serialized so two tests can't
/// race each other on the shared store.
@MainActor
@Suite("AppState · UserDefaults persistence", .serialized)
struct AppStatePersistenceTests {
    private static let keys = [
        "appMode", "isDryRun", "largeFileThresholdMB",
        "oldDownloadsAgeDays", "lifetimeScanCount", "lifetimeCleanedBytes",
    ]

    private func captureAndClear() -> [String: Any] {
        let defaults = UserDefaults.standard
        var saved: [String: Any] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                saved[key] = value
            }
            defaults.removeObject(forKey: key)
        }
        return saved
    }

    private func restore(_ saved: [String: Any]) {
        let defaults = UserDefaults.standard
        for key in Self.keys {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in saved {
            defaults.set(value, forKey: key)
        }
    }

    @Test func defaultsAreAppliedOnFreshInstall() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let state = AppState()
        #expect(state.mode == .simple)
        #expect(state.isDryRun == true) // dry run is ON by default — safety
        #expect(state.largeFileThresholdMB == 500)
        #expect(state.oldDownloadsAgeDays == 90)
        #expect(state.lifetimeScanCount == 0)
        #expect(state.lifetimeCleanedBytes == 0)
    }

    @Test func writingModeIsPersisted() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let a = AppState()
        a.mode = .advanced
        // A fresh instance reads from the same UserDefaults — if didSet
        // didn't fire, b.mode would fall back to .simple.
        let b = AppState()
        #expect(b.mode == .advanced)
    }

    @Test func writingDryRunIsPersisted() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let a = AppState()
        a.isDryRun = false
        let b = AppState()
        #expect(b.isDryRun == false)
    }

    @Test func writingThresholdIsPersisted() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let a = AppState()
        a.largeFileThresholdMB = 1024
        let b = AppState()
        #expect(b.largeFileThresholdMB == 1024)
        #expect(b.largeFileThresholdBytes == 1024 * 1024 * 1024)
    }

    @Test func writingOldDownloadsAgeIsPersisted() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let a = AppState()
        a.oldDownloadsAgeDays = 30
        let b = AppState()
        #expect(b.oldDownloadsAgeDays == 30)
    }

    @Test func lifetimeCountersAccumulateAcrossInstances() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let a = AppState()
        a.lifetimeScanCount = 5
        a.lifetimeCleanedBytes = 123_456
        let b = AppState()
        #expect(b.lifetimeScanCount == 5)
        #expect(b.lifetimeCleanedBytes == 123_456)
        // Subsequent increments persist too.
        b.lifetimeScanCount += 1
        let c = AppState()
        #expect(c.lifetimeScanCount == 6)
    }

    @Test func largeFileThresholdBytesIsDerivedFromMB() {
        let saved = captureAndClear()
        defer { restore(saved) }

        let state = AppState()
        state.largeFileThresholdMB = 256
        #expect(state.largeFileThresholdBytes == 256 * 1024 * 1024)
    }
}
