import Foundation

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
enum UpdateDownloader {
    enum Failure: Error {
        case downloadFailed
        case unzipFailed
        case fileMoveFailed
    }

    /// Download the given URL into `~/Downloads`, unzip it in place, and
    /// return the URL of the resulting `MacSift.app` bundle. Reports
    /// download progress via the supplied closure, called on the main
    /// actor with a fraction in `[0, 1]`.
    @MainActor
    static func downloadAndStage(
        from url: URL,
        version: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
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
        return appURL
    }
}
