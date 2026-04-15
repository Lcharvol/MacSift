import Foundation

@MainActor
final class ExclusionManager: ObservableObject {
    @Published private(set) var excludedPaths: [URL]
    private let defaults: UserDefaults

    init(userDefaultsSuiteName: String? = nil) {
        if let suite = userDefaultsSuiteName {
            self.defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            self.defaults = .standard
        }

        let saved = defaults.stringArray(forKey: "excludedPaths") ?? []
        // Defense in depth: a malicious process with write access to the
        // user's plist could inject garbage into excludedPaths. Exclusions
        // are subtractive so the worst case is reducing what MacSift
        // scans, but we still reject obviously-bad entries (empty
        // strings, non-absolute paths, `..` traversals) at load time so
        // the published list never contains nonsense.
        self.excludedPaths = saved.compactMap { raw in
            guard !raw.isEmpty, raw.hasPrefix("/"), !raw.contains("..") else { return nil }
            return URL(filePath: raw).standardizedFileURL
        }
    }

    func addExclusion(_ url: URL) {
        guard !excludedPaths.contains(url) else { return }
        excludedPaths.append(url)
        persist()
    }

    func removeExclusion(_ url: URL) {
        excludedPaths.removeAll { $0 == url }
        persist()
    }

    func isExcluded(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        return excludedPaths.contains { excludedURL in
            let excludedPath = excludedURL.path(percentEncoded: false)
            return path == excludedPath || path.hasPrefix(excludedPath + "/")
        }
    }

    private func persist() {
        let paths = excludedPaths.map { $0.path(percentEncoded: false) }
        defaults.set(paths, forKey: "excludedPaths")
    }
}
