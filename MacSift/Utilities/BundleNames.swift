import Foundation

/// Translates reverse-DNS bundle ids and folder names into human-readable
/// labels for the file list.
///
/// Known mappings are exact matches or prefix matches against well-known apps.
/// Unknown bundle ids fall back to a heuristic that picks the most meaningful
/// segment (skipping numeric suffixes and very short tokens like "app").
enum BundleNames {
    private static let knownApps: [(pattern: String, label: String)] = [
        ("com.apple.safari", "Safari"),
        ("com.apple.mail", "Mail"),
        ("com.apple.dt.xcode", "Xcode"),
        ("com.apple.dt", "Xcode"),
        ("com.apple.finder", "Finder"),
        ("com.apple.spotlight", "Spotlight"),
        ("com.apple.messages", "Messages"),
        ("com.apple.notes", "Notes"),
        ("com.apple.preview", "Preview"),
        ("com.apple.appstore", "App Store"),
        ("com.apple.terminal", "Terminal"),
        ("com.google.chrome", "Google Chrome"),
        ("com.google.googleusagetracking", "Google"),
        ("org.mozilla.firefox", "Firefox"),
        ("com.spotify.client", "Spotify"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.discord", "Discord"),
        ("com.figma.desktop", "Figma"),
        ("com.microsoft.vscode", "Visual Studio Code"),
        ("com.microsoft.word", "Microsoft Word"),
        ("com.microsoft.excel", "Microsoft Excel"),
        ("com.docker.docker", "Docker"),
        ("com.jetbrains", "JetBrains"),
        ("com.brave.browser", "Brave"),
        ("notion.id", "Notion"),
        ("us.zoom.xos", "Zoom"),
    ]

    /// Returns a human label for a bundle id or folder name.
    static func humanLabel(for key: String) -> String {
        let lowered = key.lowercased()

        // Exact / prefix match against known apps
        for app in knownApps {
            if lowered == app.pattern || lowered.hasPrefix(app.pattern + ".") {
                return app.label
            }
        }

        // Reverse-DNS heuristic: pick the most meaningful segment.
        if lowered.contains(".") {
            let segments = key.split(separator: ".").map(String.init)
            // Skip junk tokens at the end (numeric suffixes, "app", "framework", "helper")
            let junk: Set<String> = ["app", "framework", "helper", "service", "agent", "extension"]
            let meaningful = segments.reversed().first { segment in
                let lower = segment.lowercased()
                if junk.contains(lower) { return false }
                if Int(segment) != nil { return false }                  // pure number
                if segment.count <= 1 { return false }                   // single char
                return true
            }
            if let pick = meaningful {
                return prettify(pick)
            }
            // All segments were junk — fall through to returning the key
        }

        return prettify(key)
    }

    /// Splits a camelCase / snake_case / kebab-case string into space-separated
    /// words and capitalizes them. Leaves all-uppercase acronyms intact.
    private static func prettify(_ raw: String) -> String {
        // Replace common separators with spaces
        let withSpaces = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Insert a space before each uppercase letter that follows a lowercase one
        var result = ""
        var prevWasLower = false
        for char in withSpaces {
            if char.isUppercase && prevWasLower {
                result.append(" ")
            }
            result.append(char)
            prevWasLower = char.isLowercase
        }

        // Capitalize words but preserve all-uppercase acronyms
        let words = result.split(separator: " ").map { word -> String in
            let str = String(word)
            if str.allSatisfy({ $0.isUppercase || $0.isNumber }) && str.count > 1 {
                return str  // ACRONYM
            }
            return str.prefix(1).uppercased() + str.dropFirst()
        }
        return words.joined(separator: " ")
    }
}
