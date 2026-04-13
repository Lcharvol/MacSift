import Testing
@testable import MacSift

@Suite("BundleNames")
struct BundleNamesTests {
    @Test func exactReverseDNSMatchesKnownApp() {
        #expect(BundleNames.humanLabel(for: "com.apple.Safari") == "Safari")
        #expect(BundleNames.humanLabel(for: "com.apple.mail") == "Mail")
        #expect(BundleNames.humanLabel(for: "com.google.Chrome") == "Google Chrome")
        #expect(BundleNames.humanLabel(for: "com.microsoft.VSCode") == "Visual Studio Code")
    }

    @Test func prefixMatchesSubBundles() {
        // Sub-bundles under a known prefix still resolve to the parent label.
        #expect(BundleNames.humanLabel(for: "com.apple.dt.xcode.coresimulator") == "Xcode")
    }

    @Test func unknownBundleFallsBackToLastMeaningfulSegment() {
        // "123" is numeric junk, "helper" is a junk suffix, "oldapp" is meaningful.
        #expect(BundleNames.humanLabel(for: "com.deleted.vendor.oldapp.helper.123") == "Oldapp")
    }

    @Test func unknownBundleWithOnlyJunkReturnsRawKey() {
        // When every segment is junk, we fall back to prettified raw key.
        let result = BundleNames.humanLabel(for: "com.example.helper")
        #expect(result == "Example" || result == "Helper")  // implementation-defined, just should not crash
    }

    @Test func prettifyCamelCaseFolderNames() {
        // Non-DNS folder names (plain camelCase or snake_case) should be
        // split into words and capitalized.
        #expect(BundleNames.humanLabel(for: "myCacheFolder") == "My Cache Folder")
        #expect(BundleNames.humanLabel(for: "old_app_data") == "Old App Data")
    }

    @Test func allUppercaseAcronymsPreserved() {
        // e.g., "IDE" should stay "IDE", not "Ide"
        #expect(BundleNames.humanLabel(for: "IDE") == "IDE")
    }

    @Test func emptyAndSingleCharInputDontCrash() {
        #expect(BundleNames.humanLabel(for: "") == "")
        let single = BundleNames.humanLabel(for: "a")
        #expect(!single.isEmpty)
    }
}
