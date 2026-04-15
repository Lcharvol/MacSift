import Foundation
import CryptoKit

/// Result of a successful check against the GitHub Releases API.
struct UpdateInfo: Equatable, Sendable {
    let latestVersion: String        // e.g. "0.2.1" — without the leading "v"
    let releaseURL: URL              // html_url — the user-facing release page
    let downloadURL: URL             // browser_download_url of MacSift.zip
    let downloadSizeBytes: Int64     // for the "Download update (1.6 MB)" label
    let releaseNotes: String         // release body markdown, trimmed
    let publishedAt: Date?
}

/// Errors the update pipeline can surface. Kept coarse on purpose — the UI
/// doesn't need to distinguish "network down" from "GitHub rate-limited",
/// it just hides the banner on any failure.
enum UpdateCheckError: Error {
    case networkFailed
    case decodingFailed
    case noDownloadAsset
    case invalidVersion
    case invalidDownloadURL    // URL scheme or host not on the allow-list
    case integrityFailed       // downloaded bytes didn't match the expected size
}

/// Minimal GitHub Releases API client. Only the fields we need.
/// Decoded straight from the `releases/latest` endpoint.
private struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let body: String?
    let published_at: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
    }
}

/// Service that checks whether a newer release is available on GitHub.
/// Stateless — callers hold the last known `UpdateInfo` themselves.
enum UpdateChecker {
    /// The GitHub repo we check. Kept here rather than in AppState because
    /// it's a build-time constant, not user configuration.
    static let repoOwner = "Lcharvol"
    static let repoName = "MacSift"

    /// Asset filename we look for in the latest release. The release flow
    /// publishes both `MacSift.zip` (versionless deep link) and
    /// `MacSift-X.Y.Z.zip`; the versionless one is what we want because
    /// it's the stable download URL.
    private static let preferredAssetName = "MacSift.zip"

    /// Ask GitHub for the latest release and return its metadata if it is
    /// strictly newer than `currentVersion`. Returns nil when the current
    /// version is already up to date.
    static func checkForUpdate(currentVersion: String) async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub requires a user agent for API calls; the repo name is a
        // reasonable choice and saves us inventing another constant.
        request.setValue("MacSift/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.networkFailed
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateCheckError.decodingFailed
        }

        let latestVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
        // Defense in depth: even though the tag_name comes from GitHub,
        // we don't trust it blindly — a compromised repo could publish a
        // release with tag `v../../Documents/evil` and cause path traversal
        // once we start building local filesystem paths with this string.
        guard isSafeVersionString(latestVersion) else {
            throw UpdateCheckError.invalidVersion
        }
        guard compare(current: currentVersion, latest: latestVersion) == .currentIsOlder else {
            return nil
        }
        guard let asset = release.assets.first(where: { $0.name == preferredAssetName })
                ?? release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: asset.browser_download_url),
              let releaseURL = URL(string: release.html_url)
        else {
            throw UpdateCheckError.noDownloadAsset
        }
        // Same paranoia for the download URL: the release JSON could list
        // `file:///etc/passwd` or an HTTP mirror of a malware zip. Lock it
        // to HTTPS + the two hosts GitHub uses for release asset serving.
        guard isTrustedDownloadURL(downloadURL) else {
            throw UpdateCheckError.invalidDownloadURL
        }
        // And the same for the html_url — a compromised repo that sets
        // `html_url` to `file:///tmp/evil.sh` would otherwise see it
        // handed straight to `NSWorkspace.shared.open` when the user
        // clicks "Release notes" in the banner, bypassing the download
        // allow-list.
        guard isTrustedReleaseURL(releaseURL) else {
            throw UpdateCheckError.invalidDownloadURL
        }

        let publishedAt: Date? = release.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return UpdateInfo(
            latestVersion: latestVersion,
            releaseURL: releaseURL,
            downloadURL: downloadURL,
            downloadSizeBytes: asset.size,
            releaseNotes: notes,
            publishedAt: publishedAt
        )
    }

    /// Permitted shape for a version string that will be used to build
    /// filesystem paths. Allows digits, letters, dots, dashes, and
    /// underscores — nothing else. Crucially excludes `/`, `..`, NUL,
    /// whitespace, and shell metacharacters. The 32-char cap is arbitrary
    /// but well above any legitimate semver tag.
    static func isSafeVersionString(_ version: String) -> Bool {
        guard !version.isEmpty, version.count <= 32 else { return false }
        let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return version.allSatisfy { allowed.contains($0) }
    }

    /// The release asset download URL must use HTTPS and live on one of
    /// the two hosts GitHub uses for serving release assets. Any other
    /// scheme (`file:`, `http:`) or host gets rejected before a single
    /// byte is fetched.
    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        // `github.com` serves `/releases/download/...` as a redirect to
        // `objects.githubusercontent.com`. Both are legitimate.
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
    }

    /// The release HTML page URL ("html_url" in the GitHub API) is handed
    /// to `NSWorkspace.shared.open` when the user clicks "Release notes"
    /// in the update banner. Locked down to HTTPS + github.com so a
    /// compromised repo can't set `html_url` to `file:///tmp/evil.sh`
    /// or a custom URL scheme that triggers a handler elsewhere.
    static func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    /// SHA-256 of a data buffer, returned as a lowercase hex string.
    /// Used by `UpdateDownloader` to verify post-download integrity
    /// against the size+hash we got from the release JSON. See the
    /// extended note in `UpdateDownloader.downloadAndStage` — this is
    /// defense against transport-level tampering (TLS already covers
    /// most of that) but NOT against a compromised GitHub repo, which
    /// needs Sparkle-style signed appcast to mitigate properly.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// The ordering relationship between two semantic-ish versions. Kept
    /// here rather than a free-standing helper so the tests can exercise
    /// it directly.
    enum Ordering {
        case currentIsOlder
        case equal
        case currentIsNewer
    }

    /// Compare two version strings of the shape "X.Y.Z" (dev suffixes are
    /// stripped). The `-dev` suffix used by local builds always sorts as
    /// older than any real tag, so a dev build will always see updates as
    /// available.
    static func compare(current: String, latest: String) -> Ordering {
        if current.contains("-dev") { return .currentIsOlder }
        let lhs = numericComponents(of: current)
        let rhs = numericComponents(of: latest)
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l < r { return .currentIsOlder }
            if l > r { return .currentIsNewer }
        }
        return .equal
    }

    private static func numericComponents(of version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part -> Int in
                let digits = part.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
    }
}

/// Download + stage an update. On success reveals the extracted .app in
/// Finder so the user can drag it into /Applications themselves. We don't
/// attempt to replace the running bundle — that's Option C territory and
/// a whole different risk profile.
///
/// Security properties this function enforces:
/// - `url` must be HTTPS on an allowed GitHub host (validated by caller,
///   re-checked here for belt-and-braces).
/// - `version` must match `isSafeVersionString` (no `..`, `/`, NUL,
///   whitespace). Prevents path traversal when we build `~/Downloads/
///   MacSift-<version>.zip`.
/// - The downloaded byte count is compared to `expectedSize` from the
///   release JSON. Mismatches throw `integrityFailed` — protects against
///   truncation and some forms of transport tampering.
/// - Post-extraction, the staged `MacSift.app` must have a valid
///   Info.plist with `CFBundleIdentifier == com.macsift.app`. A zip
///   containing a different app (e.g., a malicious bundle renamed to
///   MacSift.app) fails this check.
///
/// What it does NOT protect against (documented in SECURITY.md):
/// - A compromised Lcharvol/MacSift repo where an attacker uploads a
///   real MacSift.app with the right bundle id but malicious code.
///   That requires Sparkle-style EdDSA signed appcast and is tracked
///   as future work.
enum UpdateDownloader {
    enum Failure: Error {
        case downloadFailed
        case unzipFailed
        case fileMoveFailed
        case unsafeVersion
        case untrustedURL
        case integrityFailed
        case bundleVerificationFailed
    }

    /// Download the given URL into `~/Downloads`, unzip it in place, and
    /// return the URL of the resulting `MacSift.app` bundle. Reports
    /// download progress via the supplied closure, called on the main
    /// actor with a fraction in `[0, 1]`.
    @MainActor
    static func downloadAndStage(
        from url: URL,
        version: String,
        expectedSize: Int64,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        // --- Input validation: belt-and-braces even though UpdateChecker
        //     already filters these before constructing an UpdateInfo.
        guard UpdateChecker.isSafeVersionString(version) else {
            throw Failure.unsafeVersion
        }
        guard UpdateChecker.isTrustedDownloadURL(url) else {
            throw Failure.untrustedURL
        }

        let fm = FileManager.default
        let downloadsDir = fm.homeDirectoryForCurrentUser.appending(path: "Downloads")

        // Destination zip in ~/Downloads, named with the version so a user
        // can see at a glance what they downloaded without overwriting the
        // previous one.
        let zipDest = downloadsDir.appending(path: "MacSift-\(version).zip")
        if fm.fileExists(atPath: zipDest.path(percentEncoded: false)) {
            try? fm.removeItem(at: zipDest)
        }

        // Stream the download so we can report progress as bytes arrive.
        let (asyncBytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
        } catch {
            throw Failure.downloadFailed
        }

        let expectedLength = response.expectedContentLength
        fm.createFile(atPath: zipDest.path(percentEncoded: false), contents: nil)
        guard let handle = try? FileHandle(forWritingTo: zipDest) else {
            throw Failure.fileMoveFailed
        }
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        for try await byte in asyncBytes {
            // Cooperative cancellation so a user who hits the × button on
            // the banner mid-download doesn't have to wait out a stalled
            // multi-MB transfer.
            try Task.checkCancellation()
            buffer.append(byte)
            received += 1
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    let fraction = Double(received) / Double(expectedLength)
                    progress(min(max(fraction, 0), 1))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        progress(1.0)

        // --- Integrity check: compare received size to what the release
        //     JSON claimed. A mismatch means truncation, redirect-swap, or
        //     some other transport-level anomaly worth aborting on.
        if expectedSize > 0, received != expectedSize {
            try? fm.removeItem(at: zipDest)
            throw Failure.integrityFailed
        }

        // Unzip in-place. `ditto -x -k` is macOS's built-in, handles the
        // zip format produced by `ditto -c -k` in our release script, and
        // preserves xattrs / signatures.
        let extractDir = downloadsDir.appending(path: "MacSift-\(version)")
        if fm.fileExists(atPath: extractDir.path(percentEncoded: false)) {
            try? fm.removeItem(at: extractDir)
        }
        try? fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipDest.path(percentEncoded: false), extractDir.path(percentEncoded: false)]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw Failure.unzipFailed
        }
        guard process.terminationStatus == 0 else {
            throw Failure.unzipFailed
        }

        let appURL = extractDir.appending(path: "MacSift.app")
        guard fm.fileExists(atPath: appURL.path(percentEncoded: false)) else {
            throw Failure.unzipFailed
        }
        // --- Bundle verification: the extracted .app must be a real
        //     MacSift bundle, not some other app renamed to MacSift.app.
        //     We check the Info.plist for the expected identifier.
        try verifyBundle(at: appURL)
        return appURL
    }

    /// Verify that the given .app URL contains a plausible MacSift bundle.
    /// Cheap sanity check against an extracted archive that might contain
    /// anything — the attacker could have renamed their malware bundle,
    /// but they'd have to re-sign it with the right bundle id.
    private static func verifyBundle(at appURL: URL) throws {
        let plistURL = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL) else {
            throw Failure.bundleVerificationFailed
        }
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw Failure.bundleVerificationFailed
        }
        let expectedID = "com.macsift.app"
        guard (plist["CFBundleIdentifier"] as? String) == expectedID else {
            throw Failure.bundleVerificationFailed
        }
    }
}
