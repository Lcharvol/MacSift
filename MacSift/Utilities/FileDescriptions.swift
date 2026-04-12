import Foundation

enum FileDescriptions {
    static func describe(url: URL, category: FileCategory) -> String {
        let name = url.lastPathComponent
        let path = url.path(percentEncoded: false).lowercased()

        switch category {
        case .cache:
            return describeCacheFile(name: name, path: path)
        case .logs:
            return describeLogFile(name: name, path: path)
        case .tempFiles:
            return "Temporary file: \(name)"
        case .appData:
            return "Unused app data: \(name)"
        case .largeFiles:
            return "Large file: \(name)"
        case .timeMachineSnapshots:
            return "Time Machine local snapshot"
        case .iosBackups:
            return "iOS device backup: \(name)"
        }
    }

    private static func describeCacheFile(name: String, path: String) -> String {
        let knownApps: [(pattern: String, label: String)] = [
            ("safari", "Safari"),
            ("chrome", "Google Chrome"),
            ("firefox", "Firefox"),
            ("slack", "Slack"),
            ("spotify", "Spotify"),
            ("discord", "Discord"),
            ("xcode", "Xcode"),
            ("figma", "Figma"),
        ]

        for app in knownApps {
            if path.contains(app.pattern) || name.lowercased().contains(app.pattern) {
                return "\(app.label) cache"
            }
        }
        return "Application cache: \(name)"
    }

    private static func describeLogFile(name: String, path: String) -> String {
        if path.contains("/private/var/log") {
            return "System log: \(name)"
        }
        return "Application log: \(name)"
    }
}
