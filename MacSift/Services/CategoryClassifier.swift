import Foundation

struct CategoryClassifier: Sendable {
    let largeFileThresholdBytes: Int64
    /// Age threshold in days for flagging a file in ~/Downloads as
    /// `.oldDownloads`. Defaults to 90 if not specified.
    let oldDownloadsAgeThresholdDays: Double
    /// Lowercased bundle names of installed apps, e.g. {"safari", "xcode"}.
    /// Used to detect orphaned Application Support folders.
    let installedAppBundleNames: Set<String>
    /// Home directory prefix used by all path-match rules (e.g.
    /// `/Users/foo/`). Defaults to `sharedHomePrefix` so production code
    /// matches the real user. Tests can inject a sandbox path so their
    /// fixtures classify without needing the real home layout.
    let homePrefix: String

    // MARK: - Precomputed match targets
    //
    // All of these are resolved ONCE per classifier instance (a struct built
    // once per scan) instead of per `classify` call. The shipping code built
    // each rule target with `"\(homePrefix)\(rule.suffix)"` inside the
    // per-file loop, allocating a String per rule per file; these stored
    // properties remove that entirely.

    /// Absolute, ASCII-folded rule targets in the exact order of
    /// `prefixRules`. Order is load-bearing — see `prefixRules`.
    private let resolvedRules: [(target: [UInt8], category: FileCategory)]
    private let appSupportPrefixBytes: [UInt8]
    private let appSupportPrefixCount: Int
    private let downloadsPrefixBytes: [UInt8]
    private let homePrefixBytes: [UInt8]
    private let temporaryDirectoryBytes: [UInt8]
    private static let mobileSyncBackupBytes: [UInt8] = asciiLowercasedBytes("MobileSync/Backup")

    /// Default init with an empty installed-app set. Call
    /// `CategoryClassifier.withInstalledApps(...)` to get a properly
    /// populated classifier — that function walks /Applications
    /// asynchronously off the calling thread.
    init(
        largeFileThresholdBytes: Int64 = 500 * 1024 * 1024,
        oldDownloadsAgeThresholdDays: Double = 90,
        installedAppBundleNames: Set<String> = [],
        homePrefix: String = CategoryClassifier.sharedHomePrefix
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.oldDownloadsAgeThresholdDays = oldDownloadsAgeThresholdDays
        self.installedAppBundleNames = installedAppBundleNames
        self.homePrefix = homePrefix

        // Resolve every path target to absolute ASCII-folded bytes once,
        // preserving `prefixRules` order.
        self.resolvedRules = Self.prefixRules.map { rule in
            let absolutePath = rule.absolute ? rule.suffix : homePrefix + rule.suffix
            return (Self.asciiLowercasedBytes(absolutePath), rule.category)
        }
        let appSupport = "\(homePrefix)Library/Application Support/"
        self.appSupportPrefixBytes = Self.asciiLowercasedBytes(appSupport)
        // Stored separately because the appData rule slices the ORIGINAL path
        // by this length. It must count DECOMPOSED bytes to stay aligned with
        // `appSupportPrefixBytes` (which is normalized the same way) and with
        // the NFD paths that arrive from URL.path().
        self.appSupportPrefixCount = appSupport.decomposedStringWithCanonicalMapping.utf8.count
        self.downloadsPrefixBytes = Self.asciiLowercasedBytes("\(homePrefix)Downloads/")
        self.homePrefixBytes = Self.asciiLowercasedBytes(homePrefix)
        // NSTemporaryDirectory() is a runtime value, not a compile-time
        // constant, so it is resolved here rather than in `prefixRules`.
        self.temporaryDirectoryBytes = Self.asciiLowercasedBytes(NSTemporaryDirectory())
    }

    /// Builds a classifier with the installed-app set populated from
    /// /Applications and ~/Applications. The disk walk runs on a detached
    /// task so callers on the main actor don't block.
    static func withInstalledApps(
        largeFileThresholdBytes: Int64 = 500 * 1024 * 1024,
        oldDownloadsAgeThresholdDays: Double = 90,
        homePrefix: String = CategoryClassifier.sharedHomePrefix
    ) async -> CategoryClassifier {
        let names = await Task.detached(priority: .userInitiated) {
            Self.scanInstalledAppBundleNames()
        }.value
        return CategoryClassifier(
            largeFileThresholdBytes: largeFileThresholdBytes,
            oldDownloadsAgeThresholdDays: oldDownloadsAgeThresholdDays,
            installedAppBundleNames: names,
            homePrefix: homePrefix
        )
    }

    /// Shared home directory prefix (`/Users/foo/`) used by both the
    /// classifier and `FileGrouper`, resolved once at process start. Normally the real home directory. When the app is started with
    /// `-MacSiftDemoRoot <path>` (documentation screenshots only) it resolves
    /// to that directory instead, so classification *and* grouping treat the
    /// fixture tree as the home — otherwise `FileGrouper` would fail to match
    /// `Library/Caches/<bundle id>` and collapse everything into one
    /// "System data" row.
    static let sharedHomePrefix: String = {
        let home: String
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-MacSiftDemoRoot"), i + 1 < args.count,
           !args[i + 1].isEmpty {
            // Match the spelling FileManager's enumerator actually reports.
            // resolvingSymlinksInPath collapses /private/tmp down to /tmp,
            // but scanned paths keep the /private prefix — so put it back,
            // otherwise the prefix never matches and every file falls into
            // the "System data" bucket.
            let resolved = URL(filePath: args[i + 1]).resolvingSymlinksInPath()
                .path(percentEncoded: false)
            if resolved == "/tmp" || resolved.hasPrefix("/tmp/")
                || resolved == "/var" || resolved.hasPrefix("/var/") {
                home = "/private" + resolved
            } else {
                home = resolved
            }
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        }
        return home.hasSuffix("/") ? home : home + "/"
    }()

    /// Walks /Applications and ~/Applications once at init and collects the
    /// lowercased bundle base names. Used to flag Application Support folders
    /// whose owner app is no longer installed.
    static func scanInstalledAppBundleNames() -> Set<String> {
        let fm = FileManager.default
        let roots: [URL] = [
            URL(filePath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        var names = Set<String>()
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                let base = entry.deletingPathExtension().lastPathComponent.lowercased()
                names.insert(base)
                // Also store the simplified one-word version for fuzzy matching:
                // "Visual Studio Code" → "vscode" / "code"
                let words = base.split(separator: " ")
                if words.count > 1 {
                    names.insert(words.joined())
                }
                if let last = words.last {
                    names.insert(String(last))
                }
            }
        }
        return names
    }

    /// Returns true if the given Application Support subfolder belongs to an
    /// installed app. The folder name is matched case-insensitively against
    /// the cached set of installed app names.
    ///
    /// This is already case-safe and needs no change for the case-insensitive
    /// path fix: it lowercases the incoming folder name, and
    /// `scanInstalledAppBundleNames` lowercases everything it inserts, so both
    /// sides of the comparison are folded. It runs only for paths that already
    /// matched the Application Support prefix (a small fraction of a scan), so
    /// the `lowercased()` allocation here is not on the hot path.
    func isOrphanedAppSupport(folderName: String) -> Bool {
        let key = folderName.lowercased()
        if installedAppBundleNames.contains(key) { return false }
        // Many apps use reverse-DNS folders like "com.apple.Safari" — match the
        // last segment against installed app names.
        if let lastSegment = key.split(separator: ".").last {
            if installedAppBundleNames.contains(String(lastSegment)) { return false }
        }
        return true
    }

    // MARK: - Case-insensitive path matching

    /// macOS boot volumes are case-INSENSITIVE by default, so a directory
    /// whose real on-disk name is `library` or `DOWNLOADS` can exist — and it
    /// is the *only* name for it (you cannot create a case-variant sibling).
    /// Every path rule below therefore has to match without regard to case,
    /// or files under such a directory are misclassified or silently dropped.
    ///
    /// We fold to lowercase over raw UTF-8 bytes, ASCII-only, rather than
    /// using `lowercased()` or `.caseInsensitive`/`localizedCaseInsensitive*`:
    /// `classify` runs once per scanned file (177k+ on a real scan), and it is
    /// one of the hottest functions in the app. Measured over 100k synthetic
    /// paths: the shipping case-sensitive version took 319 ms, this byte fold
    /// takes 29 ms, `lowercased()`-per-call takes 212 ms, and
    /// `range(of:options:.caseInsensitive)` per rule takes 1873 ms.
    ///
    /// ASCII-only is not a compromise here: every rule suffix is pure ASCII,
    /// so no non-ASCII byte can ever participate in a case difference that
    /// matters. Bytes >= 0x80 (including every UTF-8 continuation byte) pass
    /// through untouched, so a non-ASCII username in `homePrefix` still
    /// matches byte-for-byte.
    @inline(__always)
    private static func asciiLowercased(_ byte: UInt8) -> UInt8 {
        // 'A'...'Z' -> 'a'...'z'
        (byte >= 0x41 && byte <= 0x5A) ? byte &+ 32 : byte
    }

    /// Folds a string to lowercase ASCII bytes. Used for the rule targets at
    /// init time and for the incoming path once per `classify` call.
    ///
    /// The incoming paths we compare against come from
    /// `URL.path(percentEncoded:)`, which returns non-ASCII decomposed (NFD):
    /// "é" arrives as `65 cc 81`, not `c3 a9`. A `homePrefix` built from a
    /// plain Swift string literal is composed (NFC), so the two would differ
    /// byte-wise even though Swift's `==` calls them equal. Normalizing the
    /// targets through `decomposedStringWithCanonicalMapping` here puts both
    /// sides in the same form. (This only affects non-ASCII usernames; every
    /// rule suffix is pure ASCII and unchanged by normalization.)
    private static func asciiLowercasedBytes(_ string: String) -> [UInt8] {
        var bytes = Array(string.decomposedStringWithCanonicalMapping.utf8)
        for index in bytes.indices {
            bytes[index] = asciiLowercased(bytes[index])
        }
        return bytes
    }

    /// Byte-wise prefix test. Both sides are already ASCII-folded.
    @inline(__always)
    private static func hasPrefix(_ haystack: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard haystack.count >= needle.count else { return false }
        for index in 0..<needle.count where haystack[index] != needle[index] {
            return false
        }
        return true
    }

    /// Byte-wise substring test. Both sides are already ASCII-folded.
    @inline(__always)
    private static func contains(_ haystack: UnsafeBufferPointer<UInt8>, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        let limit = haystack.count - needle.count
        let firstByte = needle[0]
        var start = 0
        while start <= limit {
            if haystack[start] == firstByte {
                var offset = 1
                while offset < needle.count && haystack[start + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    /// Declarative prefix-based rules, tried in order. Each entry is an
    /// `(absolute path prefix, category)` pair. The first hit wins, so the
    /// ordering here is load-bearing — more specific rules come before the
    /// generic ones (e.g., Xcode's DerivedData must precede a generic
    /// `Library/Caches` match). Rules that aren't pure prefix checks
    /// (orphaned appData, age-based Old Downloads, size-based Large Files)
    /// live in the tail of `classify` below.
    ///
    /// These are relative suffixes; `resolvedRules` (built once per
    /// classifier instance) turns them into absolute ASCII-folded byte
    /// targets, preserving this order exactly.
    private static let prefixRules: [(suffix: String, absolute: Bool, category: FileCategory)] = [
        // Xcode / developer artifacts under ~/Library/Developer
        ("Library/Developer/Xcode/DerivedData", false, .xcodeJunk),
        ("Library/Developer/Xcode/Archives", false, .xcodeJunk),
        ("Library/Developer/Xcode/iOS DeviceSupport", false, .xcodeJunk),
        ("Library/Developer/Xcode/watchOS DeviceSupport", false, .xcodeJunk),
        ("Library/Developer/Xcode/tvOS DeviceSupport", false, .xcodeJunk),
        ("Library/Developer/Xcode/UserData/IB Support", false, .xcodeJunk),
        ("Library/Developer/CoreSimulator/Caches", false, .xcodeJunk),
        // Mail attachments — must precede the generic Caches rule since the
        // app-sandbox copy lives under Library/Containers.
        ("Library/Mail Downloads", false, .mailDownloads),
        ("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", false, .mailDownloads),
        // Developer package manager caches
        (".npm", false, .devCaches),
        (".yarn", false, .devCaches),
        (".pnpm-store", false, .devCaches),
        (".cache/pip", false, .devCaches),
        (".cache/huggingface", false, .devCaches),
        (".cache/yarn", false, .devCaches),
        (".cargo/registry/cache", false, .devCaches),
        (".rustup/toolchains", false, .devCaches),
        ("go/pkg/mod", false, .devCaches),
        ("Library/Caches/Homebrew", false, .devCaches),
        ("Library/Caches/pip", false, .devCaches),
        ("Library/Caches/com.apple.dt.Xcode", false, .devCaches),
        // Generic categories — must come after the more specific dev / Xcode
        // rules above.
        ("Library/Caches", false, .cache),
        ("Library/Logs", false, .logs),
        // Absolute-path system roots
        ("/private/var/log", true, .logs),
        ("/tmp", true, .tempFiles),
    ]

    /// Classifies one scanned file. Rule order is exactly as documented in
    /// CLAUDE.md: iOS Backups -> Xcode Junk -> Mail -> Dev Caches -> Caches
    /// -> Logs -> Temp -> Orphan AppData -> Old Downloads -> Large Files.
    ///
    /// All path matching is ASCII-case-insensitive because macOS boot volumes
    /// are case-insensitive by default — see `asciiLowercased` above. The
    /// incoming path is folded exactly once per call.
    func classify(url: URL, size: Int64, modificationDate: Date = .distantPast) -> FileCategory? {
        let path = url.path(percentEncoded: false)

        // Fold the path to lowercase ASCII bytes ONCE for this call. Every
        // rule below compares against this same buffer.
        var folded = Array(path.utf8)
        for index in folded.indices {
            folded[index] = Self.asciiLowercased(folded[index])
        }

        // `matched` carries the decision out of the byte-pointer scope.
        // `.appData` needs the original path, so it is resolved after.
        enum Match {
            case category(FileCategory)
            case appDataCandidate
            case downloadsCandidate
            case none
        }

        let matched: Match = folded.withUnsafeBufferPointer { buffer in
            // iOS Backups (check before general appData)
            if Self.contains(buffer, Self.mobileSyncBackupBytes) {
                return .category(.iosBackups)
            }

            // Walk the declarative rules once, in table order.
            for rule in resolvedRules where Self.hasPrefix(buffer, rule.target) {
                return .category(rule.category)
            }

            if Self.hasPrefix(buffer, temporaryDirectoryBytes) {
                return .category(.tempFiles)
            }

            if Self.hasPrefix(buffer, appSupportPrefixBytes) {
                return .appDataCandidate
            }

            if Self.hasPrefix(buffer, downloadsPrefixBytes) {
                return .downloadsCandidate
            }

            if Self.hasPrefix(buffer, homePrefixBytes) {
                return .none
            }
            // Outside the home directory entirely and matched no absolute
            // rule: not ours. Signalled by returning .none and failing the
            // home check again below.
            return .none
        }

        switch matched {
        case .category(let category):
            return category

        case .appDataCandidate:
            // Application Support: only classify as .appData if the parent
            // folder belongs to an app that is no longer installed (orphaned
            // data). Slice the ORIGINAL path, not the folded bytes, so
            // `isOrphanedAppSupport` sees the real on-disk casing (it does
            // its own case-insensitive comparison).
            let relative = String(decoding: Array(path.utf8).dropFirst(appSupportPrefixCount), as: UTF8.self)
            let firstComponent = relative.split(separator: "/").first.map(String.init) ?? ""
            return isOrphanedAppSupport(folderName: firstComponent) ? .appData : nil

        case .downloadsCandidate:
            // Old Downloads — files in ~/Downloads that haven't been touched
            // in a while. The threshold is age-based, not size-based. Recent
            // files fall through to the .largeFiles check below so they're
            // still flagged if they're big.
            let ageDays = Date().timeIntervalSince(modificationDate) / 86_400
            if ageDays >= oldDownloadsAgeThresholdDays {
                return .oldDownloads
            }
            // Recent Downloads file: it is by definition under homePrefix, so
            // the only remaining question is size.
            return size > largeFileThresholdBytes ? .largeFiles : nil

        case .none:
            // Large files (anywhere in home)
            let isInHome = folded.withUnsafeBufferPointer {
                Self.hasPrefix($0, homePrefixBytes)
            }
            if isInHome && size > largeFileThresholdBytes {
                return .largeFiles
            }
            return nil
        }
    }

}
