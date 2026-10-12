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

    // MARK: - Orphaned app support

    @Test func orphanedAppSupportIsDetectedAsAppData() {
        // Use a classifier with NO installed apps so everything in
        // Application Support is considered orphaned.
        let classifier = CategoryClassifier(installedAppBundleNames: [])
        let url = home.appending(path: "Library/Application Support/com.vendor.deletedapp/Data.db")
        #expect(classifier.classify(url: url, size: 1000) == .appData)
    }

    @Test func installedAppSupportIsLeftAlone() {
        // Safari is "installed" — its folder should NOT be flagged.
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        let url = home.appending(path: "Library/Application Support/com.apple.Safari/Bookmarks.plist")
        #expect(classifier.classify(url: url, size: 1000) == nil)
    }

    @Test func isOrphanedAppSupportMatchesExactName() {
        let classifier = CategoryClassifier(installedAppBundleNames: ["notion"])
        #expect(classifier.isOrphanedAppSupport(folderName: "Notion") == false)
        #expect(classifier.isOrphanedAppSupport(folderName: "notion") == false)
        #expect(classifier.isOrphanedAppSupport(folderName: "Obsidian") == true)
    }

    @Test func isOrphanedAppSupportMatchesReverseDNS() {
        // Reverse-DNS folder names like "com.apple.Safari" should match against
        // the "safari" entry in the installed set.
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        #expect(classifier.isOrphanedAppSupport(folderName: "com.apple.Safari") == false)
    }

    @Test func isOrphanedAppSupportFlagsUnknownVendors() {
        let classifier = CategoryClassifier(installedAppBundleNames: ["safari"])
        #expect(classifier.isOrphanedAppSupport(folderName: "com.deleted.vendor.oldapp") == true)
    }

    // MARK: - Xcode Junk

    @Test func classifiesXcodeDerivedData() {
        let url = home.appending(path: "Library/Developer/Xcode/DerivedData/MyApp-abc/Build/Products/Debug/MyApp.app/MyApp")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesXcodeArchives() {
        let url = home.appending(path: "Library/Developer/Xcode/Archives/2025-11-01/MyApp 2025-11-01 10.00.xcarchive/Info.plist")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesIOSDeviceSupport() {
        let url = home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)/Symbols/usr/lib/dyld")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    @Test func classifiesCoreSimulatorCaches() {
        let url = home.appending(path: "Library/Developer/CoreSimulator/Caches/dyld/abc123/dyld_shared_cache_arm64e")
        #expect(classifier.classify(url: url, size: 1000) == .xcodeJunk)
    }

    // MARK: - Dev Caches

    @Test func classifiesNpmCache() {
        let url = home.appending(path: ".npm/_cacache/content-v2/sha512/ab/cd.gz")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesHomebrewCache() {
        let url = home.appending(path: "Library/Caches/Homebrew/downloads/ffmpeg.tar.gz")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesGoModuleCache() {
        let url = home.appending(path: "go/pkg/mod/github.com/foo/bar/baz.go")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    @Test func classifiesCargoRegistryCache() {
        let url = home.appending(path: ".cargo/registry/cache/index.crates.io-abc/tokio-1.0.0.crate")
        #expect(classifier.classify(url: url, size: 1000) == .devCaches)
    }

    // MARK: - Old Downloads

    @Test func classifiesOldDownloadAsOldDownloads() {
        let url = home.appending(path: "Downloads/Some-installer.dmg")
        let oldDate = Date().addingTimeInterval(-100 * 86400)  // 100 days ago
        #expect(classifier.classify(url: url, size: 1000, modificationDate: oldDate) == .oldDownloads)
    }

    @Test func doesNotClassifyRecentDownloadAsOld() {
        let url = home.appending(path: "Downloads/Recent.pdf")
        let recentDate = Date().addingTimeInterval(-5 * 86400)  // 5 days ago
        #expect(classifier.classify(url: url, size: 1000, modificationDate: recentDate) == nil)
    }

    @Test func recentLargeDownloadClassifiesAsLargeFiles() {
        // Regression: previously a recent file in ~/Downloads returned nil
        // regardless of size. After the double-count fix, recent files fall
        // through to the .largeFiles check and big ones are still flagged.
        let url = home.appending(path: "Downloads/RecentInstaller.dmg")
        let recent = Date().addingTimeInterval(-5 * 86400)
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1, modificationDate: recent) == .largeFiles)
    }

    @Test func oldLargeDownloadPrefersOldDownloads() {
        // A file that matches both .oldDownloads (age) and .largeFiles (size)
        // should be classified as .oldDownloads — that check runs first.
        let url = home.appending(path: "Downloads/OldBigVideo.mov")
        let old = Date().addingTimeInterval(-200 * 86400)
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: url, size: threshold + 1, modificationDate: old) == .oldDownloads)
    }

    @Test func configurableOldDownloadsThreshold() {
        // Custom classifier with a tight 30-day threshold: a 45-day-old file
        // qualifies as .oldDownloads. With the default 90-day threshold it
        // would not.
        let strict = CategoryClassifier(oldDownloadsAgeThresholdDays: 30)
        let url = home.appending(path: "Downloads/lastMonth.zip")
        let fortyFiveDaysAgo = Date().addingTimeInterval(-45 * 86400)
        #expect(strict.classify(url: url, size: 1000, modificationDate: fortyFiveDaysAgo) == .oldDownloads)

        let lax = CategoryClassifier(oldDownloadsAgeThresholdDays: 180)
        #expect(lax.classify(url: url, size: 1000, modificationDate: fortyFiveDaysAgo) == nil)
    }

    // MARK: - Mail Attachments

    @Test func classifiesMailDownloads() {
        let url = home.appending(path: "Library/Mail Downloads/abc123/attachment.pdf")
        #expect(classifier.classify(url: url, size: 1000) == .mailDownloads)
    }

    @Test func classifiesMailContainerDownloads() {
        let url = home.appending(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/xyz/photo.jpg")
        #expect(classifier.classify(url: url, size: 1000) == .mailDownloads)
    }
}

// MARK: - Case-insensitive path matching

/// macOS boot volumes are case-insensitive by default, so a directory whose
/// real on-disk name is `library`, `DOWNLOADS` or `Library/caches` can exist —
/// and that is the ONLY name for it (you cannot create a case-variant
/// sibling). Before the fix, every rule in `classify` used a case-sensitive
/// `hasPrefix`, so such a directory missed its rule entirely: files under it
/// were either misclassified as `.largeFiles` or silently dropped (`nil`),
/// making e.g. `~/library/Caches` effectively unscannable.
///
/// These tests inject a sandbox `homePrefix` rather than depending on the real
/// home layout.
@Suite("CategoryClassifier · case-insensitive paths")
struct CategoryClassifierCaseInsensitivityTests {
    /// Sandbox home prefix. Nothing here touches the real filesystem — the
    /// classifier is a pure path-matching function.
    let sandboxHome = "/Users/sandboxuser/"

    private func makeClassifier(
        largeFileThresholdBytes: Int64 = 500 * 1024 * 1024,
        oldDownloadsAgeThresholdDays: Double = 90,
        installedAppBundleNames: Set<String> = []
    ) -> CategoryClassifier {
        CategoryClassifier(
            largeFileThresholdBytes: largeFileThresholdBytes,
            oldDownloadsAgeThresholdDays: oldDownloadsAgeThresholdDays,
            installedAppBundleNames: installedAppBundleNames,
            homePrefix: sandboxHome
        )
    }

    private func url(_ relativePath: String) -> URL {
        URL(filePath: sandboxHome + relativePath)
    }

    // MARK: Lowercase / uppercase directory names

    @Test func lowercaseLibraryCachesStillClassifiesAsCache() {
        // The headline bug: a real on-disk `~/library/Caches` was unscannable.
        let classifier = makeClassifier()
        #expect(classifier.classify(url: url("library/Caches/x"), size: 1000) == .cache)
    }

    @Test func lowercaseLibraryCachesIsNotSilentlyDropped() {
        // Before the fix this returned nil for a small file (silently dropped)
        // and .largeFiles for a big one (misclassified).
        let classifier = makeClassifier()
        let small = classifier.classify(url: url("library/caches/com.app/blob.db"), size: 1000)
        #expect(small == .cache)

        let threshold: Int64 = 500 * 1024 * 1024
        let large = classifier.classify(url: url("library/caches/com.app/blob.db"), size: threshold + 1)
        #expect(large == .cache)
        #expect(large != .largeFiles)
    }

    @Test func uppercaseDownloadsStillClassifiesAsOldDownloads() {
        // Before the fix `~/DOWNLOADS/big.bin` fell through to .largeFiles.
        let classifier = makeClassifier()
        let old = Date().addingTimeInterval(-120 * 86400)
        #expect(classifier.classify(url: url("DOWNLOADS/old.bin"), size: 1000, modificationDate: old) == .oldDownloads)
    }

    @Test func uppercaseLargeDownloadIsNotMisclassifiedAsLargeFiles() {
        let classifier = makeClassifier()
        let old = Date().addingTimeInterval(-120 * 86400)
        let threshold: Int64 = 500 * 1024 * 1024
        let category = classifier.classify(url: url("DOWNLOADS/big.bin"), size: threshold + 1, modificationDate: old)
        #expect(category == .oldDownloads)
        #expect(category != .largeFiles)
    }

    @Test func uppercaseLibraryLogsStillClassifiesAsLogs() {
        let classifier = makeClassifier()
        #expect(classifier.classify(url: url("LIBRARY/Logs/x"), size: 1000) == .logs)
    }

    // MARK: Rule ordering must survive the case fix

    @Test func mixedCaseDerivedDataClassifiesAsXcodeJunkNotCache() {
        // Ordering proof: DerivedData lives under Library/Developer, but the
        // real ordering hazard documented in CLAUDE.md is that the Xcode rules
        // must precede the generic Library/Caches rule. If case-folding had
        // reordered or broken the table, a mixed-case path could fall to a
        // later rule. It must still be .xcodeJunk.
        let classifier = makeClassifier()
        let path = "LIBRARY/developer/XCODE/deriveddata/MyApp-abc/Build/obj.o"
        #expect(classifier.classify(url: url(path), size: 1000) == .xcodeJunk)
    }

    @Test func mixedCaseCoreSimulatorCachesBeatsGenericCacheRule() {
        // The strongest ordering test: CoreSimulator caches live UNDER
        // Library/Caches-adjacent paths and CLAUDE.md calls out that the Xcode
        // Junk check must come BEFORE .cache. Mixed case must not flip this.
        let classifier = makeClassifier()
        let path = "library/Developer/coresimulator/CACHES/dyld/abc/cache"
        let category = classifier.classify(url: url(path), size: 1000)
        #expect(category == .xcodeJunk)
        #expect(category != .cache)
    }

    @Test func mixedCaseHomebrewCacheBeatsGenericCacheRule() {
        // Library/Caches/Homebrew (.devCaches) precedes Library/Caches
        // (.cache). Verify the more specific rule still wins when cased oddly.
        let classifier = makeClassifier()
        let category = classifier.classify(url: url("Library/CACHES/homebrew/downloads/x.tar.gz"), size: 1000)
        #expect(category == .devCaches)
        #expect(category != .cache)
    }

    @Test func mixedCaseMailDownloadsBeatsGenericCacheRule() {
        let classifier = makeClassifier()
        let path = "library/containers/COM.APPLE.MAIL/Data/library/mail downloads/x/a.pdf"
        #expect(classifier.classify(url: url(path), size: 1000) == .mailDownloads)
    }

    // MARK: Other rules

    @Test func mixedCaseIOSBackupStillClassifies() {
        let classifier = makeClassifier()
        let path = "Library/Application Support/mobilesync/backup/abc123/Info.plist"
        #expect(classifier.classify(url: url(path), size: 1000) == .iosBackups)
    }

    @Test func mixedCaseDevCacheStillClassifies() {
        let classifier = makeClassifier()
        #expect(classifier.classify(url: url(".NPM/_cacache/content/x"), size: 1000) == .devCaches)
        #expect(classifier.classify(url: url("GO/pkg/MOD/github.com/f/b.go"), size: 1000) == .devCaches)
    }

    @Test func mixedCaseAbsoluteSystemRulesStillClassify() {
        let classifier = makeClassifier()
        #expect(classifier.classify(url: URL(filePath: "/PRIVATE/var/LOG/system.log"), size: 1000) == .logs)
        #expect(classifier.classify(url: URL(filePath: "/TMP/scratch.dat"), size: 1000) == .tempFiles)
    }

    @Test func mixedCaseOrphanAppSupportStillClassifies() {
        let classifier = makeClassifier(installedAppBundleNames: [])
        let path = "library/application support/com.vendor.deletedapp/Data.db"
        #expect(classifier.classify(url: url(path), size: 1000) == .appData)
    }

    @Test func mixedCaseInstalledAppSupportIsStillLeftAlone() {
        // The folder-name casing must still reach isOrphanedAppSupport intact
        // enough to match the installed set, even when the PREFIX was cased
        // oddly. Regression guard for the byte-slice that extracts it.
        let classifier = makeClassifier(installedAppBundleNames: ["safari"])
        let path = "LIBRARY/Application Support/com.apple.Safari/Bookmarks.plist"
        #expect(classifier.classify(url: url(path), size: 1000) == nil)
    }

    @Test func mixedCaseHomePrefixStillFlagsLargeFiles() {
        let classifier = makeClassifier()
        let threshold: Int64 = 500 * 1024 * 1024
        let oddCaseHome = URL(filePath: "/users/SANDBOXUSER/Movies/huge.mov")
        #expect(classifier.classify(url: oddCaseHome, size: threshold + 1) == .largeFiles)
    }

    @Test func pathsOutsideHomeAreStillUnclassified() {
        // Widening must not start claiming files outside the home directory.
        let classifier = makeClassifier()
        let threshold: Int64 = 500 * 1024 * 1024
        #expect(classifier.classify(url: URL(filePath: "/Volumes/External/huge.mov"), size: threshold + 1) == nil)
        #expect(classifier.classify(url: URL(filePath: "/opt/homebrew/bin/tool"), size: 1000) == nil)
    }

    // MARK: Pure-widening regression guard

    @Test func correctlyCasedPathsAreUnchanged() {
        // The fix must be a PURE WIDENING: every input that classified as X
        // before must still classify as X. This table is the canonical-casing
        // expectation set, asserted against the sandbox home.
        let classifier = makeClassifier(installedAppBundleNames: ["safari"])
        let threshold: Int64 = 500 * 1024 * 1024
        let old = Date().addingTimeInterval(-120 * 86400)
        let recent = Date().addingTimeInterval(-5 * 86400)

        let cases: [(path: String, size: Int64, date: Date, expected: FileCategory?)] = [
            ("Library/Caches/com.apple.Safari/x.db", 1000, .distantPast, .cache),
            ("Library/Logs/DiagnosticReports/crash.log", 1000, .distantPast, .logs),
            ("Library/Developer/Xcode/DerivedData/App-abc/obj.o", 1000, .distantPast, .xcodeJunk),
            ("Library/Developer/Xcode/Archives/2025-11-01/a.xcarchive/Info.plist", 1000, .distantPast, .xcodeJunk),
            ("Library/Developer/CoreSimulator/Caches/dyld/abc/c", 1000, .distantPast, .xcodeJunk),
            ("Library/Mail Downloads/abc/a.pdf", 1000, .distantPast, .mailDownloads),
            ("Library/Caches/Homebrew/downloads/f.tar.gz", 1000, .distantPast, .devCaches),
            (".npm/_cacache/content-v2/x", 1000, .distantPast, .devCaches),
            ("go/pkg/mod/github.com/f/b.go", 1000, .distantPast, .devCaches),
            (".cargo/registry/cache/idx/tokio.crate", 1000, .distantPast, .devCaches),
            ("Library/Application Support/MobileSync/Backup/abc/Info.plist", 1000, .distantPast, .iosBackups),
            ("Library/Application Support/com.vendor.gone/Data.db", 1000, .distantPast, .appData),
            ("Library/Application Support/com.apple.Safari/Bookmarks.plist", 1000, .distantPast, nil),
            ("Downloads/old-installer.dmg", 1000, old, .oldDownloads),
            ("Downloads/recent.pdf", 1000, recent, nil),
            ("Downloads/recent-big.dmg", threshold + 1, recent, .largeFiles),
            ("Downloads/old-big.mov", threshold + 1, old, .oldDownloads),
            ("Documents/huge_video.mov", threshold + 1, .distantPast, .largeFiles),
            ("Documents/small.txt", 1000, .distantPast, nil),
        ]

        for testCase in cases {
            let actual = classifier.classify(
                url: url(testCase.path),
                size: testCase.size,
                modificationDate: testCase.date
            )
            #expect(
                actual == testCase.expected,
                "\(testCase.path) expected \(String(describing: testCase.expected)) got \(String(describing: actual))"
            )
        }
    }

    @Test func absolutePathRulesAreUnchanged() {
        let classifier = makeClassifier()
        #expect(classifier.classify(url: URL(filePath: "/private/var/log/system.log"), size: 1000) == .logs)
        #expect(classifier.classify(url: URL(filePath: "/tmp/scratch.dat"), size: 1000) == .tempFiles)
    }

    @Test func nonASCIIUsernameInHomePrefixStillMatches() {
        // ASCII-only folding is deliberate: bytes >= 0x80 pass through
        // untouched, so a non-ASCII username still matches byte-for-byte while
        // the ASCII portion of the path folds.
        //
        // The subtlety: URL(filePath:) returns non-ASCII DECOMPOSED (NFD), so
        // "é" arrives as 65 cc 81, while this NFC string literal is c3 a9.
        // `asciiLowercasedBytes` normalizes the stored targets to NFD so both
        // sides agree. Without that, every file under a non-ASCII home would
        // be silently dropped.
        let classifier = CategoryClassifier(homePrefix: "/Users/José/")
        #expect(classifier.classify(url: URL(filePath: "/Users/José/Library/Caches/x"), size: 1000) == .cache)
        #expect(classifier.classify(url: URL(filePath: "/Users/José/library/caches/x"), size: 1000) == .cache)
    }

    @Test func nonASCIIHomePrefixWorksForBothUnicodeNormalizations() {
        // Whichever way the caller spells the home prefix, the classifier must
        // agree with the NFD paths that URL.path() produces.
        let nfcHome = "/Users/Jos\u{00E9}/"        // composed  é
        let nfdHome = "/Users/Jose\u{0301}/"       // decomposed e + ´
        for home in [nfcHome, nfdHome] {
            let classifier = CategoryClassifier(homePrefix: home)
            for spelling in [nfcHome, nfdHome] {
                let url = URL(filePath: spelling + "Library/Caches/x")
                #expect(
                    classifier.classify(url: url, size: 1000) == .cache,
                    "home=\(home.unicodeScalars.count) path=\(spelling.unicodeScalars.count)"
                )
            }
        }
    }

    @Test func nonASCIIHomePrefixStillFlagsLargeFilesAndNotOutsiders() {
        // Guards the tail of `classify` for non-ASCII homes: the home-prefix
        // check is what decides .largeFiles vs nil.
        let classifier = CategoryClassifier(homePrefix: "/Users/José/")
        let threshold: Int64 = 500 * 1024 * 1024
        let inHome = URL(filePath: "/Users/José/Movies/huge.mov")
        #expect(classifier.classify(url: inHome, size: threshold + 1) == .largeFiles)
        let outside = URL(filePath: "/Users/SomebodyElse/Movies/huge.mov")
        #expect(classifier.classify(url: outside, size: threshold + 1) == nil)
    }

    @Test func nonASCIIHomePrefixOrphanAppSupportSlicesFolderNameCorrectly() {
        // The appData branch slices the original path by a stored BYTE count.
        // With a non-ASCII home that count must be the decomposed length, or
        // the extracted folder name is offset and orphan detection misfires.
        let classifier = CategoryClassifier(
            installedAppBundleNames: ["safari"],
            homePrefix: "/Users/José/"
        )
        let orphan = URL(filePath: "/Users/José/Library/Application Support/com.vendor.gone/D.db")
        #expect(classifier.classify(url: orphan, size: 1000) == .appData)
        let installed = URL(filePath: "/Users/José/Library/Application Support/com.apple.Safari/B.plist")
        #expect(classifier.classify(url: installed, size: 1000) == nil)
    }
}
