import Testing
@testable import MacSift

@Suite("Update version compare")
struct UpdateCheckerVersionCompareTests {
    @Test func equalVersionsAreEqual() {
        #expect(UpdateChecker.compare(current: "0.2.0", latest: "0.2.0") == .equal)
        #expect(UpdateChecker.compare(current: "1.0.0", latest: "1.0.0") == .equal)
    }

    @Test func newerPatchIsOlder() {
        #expect(UpdateChecker.compare(current: "0.1.9", latest: "0.1.10") == .currentIsOlder)
    }

    @Test func newerMinorIsOlder() {
        #expect(UpdateChecker.compare(current: "0.1.9", latest: "0.2.0") == .currentIsOlder)
    }

    @Test func newerMajorIsOlder() {
        #expect(UpdateChecker.compare(current: "0.9.0", latest: "1.0.0") == .currentIsOlder)
    }

    @Test func currentAheadIsNewer() {
        #expect(UpdateChecker.compare(current: "0.3.0", latest: "0.2.0") == .currentIsNewer)
    }

    @Test func devSuffixIsAlwaysOlder() {
        #expect(UpdateChecker.compare(current: "0.0.0-dev", latest: "0.1.0") == .currentIsOlder)
        // Even if the dev version number is higher, dev is older.
        #expect(UpdateChecker.compare(current: "99.0.0-dev", latest: "0.1.0") == .currentIsOlder)
    }

    @Test func missingComponentsDefaultToZero() {
        #expect(UpdateChecker.compare(current: "0.2", latest: "0.2.0") == .equal)
        #expect(UpdateChecker.compare(current: "0.2", latest: "0.2.1") == .currentIsOlder)
    }
}
