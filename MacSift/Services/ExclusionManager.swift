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
        self.excludedPaths = saved.map { URL(filePath: $0) }
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
