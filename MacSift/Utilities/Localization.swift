import Foundation

/// User-facing app language. `.system` falls back to whatever macOS resolves
/// against `Locale.preferredLanguages`. The other cases force a specific
/// `.lproj` bundle regardless of system settings.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese
    case french

    var id: String { rawValue }

    /// Bundle localization identifier (matches the `.lproj` folder name).
    /// `nil` means "let the system decide".
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .french: "fr"
        }
    }

    /// Locale to inject via `.environment(\.locale, …)` so SwiftUI re-renders
    /// `Text("key")` against the right bundle. For `.system` we mirror the
    /// current system locale rather than picking one arbitrarily.
    var locale: Locale {
        Locale(identifier: localeIdentifier ?? Locale.current.identifier)
    }

    var displayName: String {
        switch self {
        case .system: String(localized: "language.system", defaultValue: "System")
        case .english: String(localized: "language.english", defaultValue: "English")
        case .simplifiedChinese: String(localized: "language.simplifiedChinese", defaultValue: "Simplified Chinese")
        case .french: String(localized: "language.french", defaultValue: "French")
        }
    }
}

/// Localization helper for **non-SwiftUI** call sites (services that build
/// strings outside a `View.body`, where `.environment(\.locale, …)` does not
/// reach). SwiftUI views must keep using `Text("…")` / `String(localized:)`
/// so they re-render automatically when the locale environment changes.
enum L10n {
    private static let languageKey = "appLanguage"

    /// Cache resolved bundles so the per-file scan paths (`FileDescriptions`,
    /// `FileGrouper`) don't hit the filesystem on every call.
    private static let bundleCache = BundleCache()

    private final class BundleCache: @unchecked Sendable {
        private var cache: [String: Bundle] = [:]
        private let lock = NSLock()

        func bundle(for identifier: String, resolve: () -> Bundle) -> Bundle {
            lock.lock(); defer { lock.unlock() }
            if let cached = cache[identifier] { return cached }
            let resolved = resolve()
            cache[identifier] = resolved
            return resolved
        }
    }

    /// The user's currently selected language, read from `UserDefaults`.
    static var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// Persist the user's language choice. The `.environment(\.locale, …)`
    /// in `MacSiftApp` watches `AppState.language` and re-renders views; this
    /// `UserDefaults` write is what services read for non-view lookups.
    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    /// Look up `key` in the bundle matching `locale`. If `locale` is `nil`,
    /// uses the user's selected language. Falls back to the development
    /// language (`en`) if the locale has no matching `.lproj`.
    static func text(_ key: String, defaultValue: String, locale: Locale? = nil) -> String {
        let resolved = bundle(for: locale ?? currentLanguage.locale)
        let result = resolved.localizedString(forKey: key, value: defaultValue, table: nil)
        return result == key ? defaultValue : result
    }

    /// `printf`-style formatting that respects the chosen locale for number /
    /// argument substitution. Used by services that need to compose strings
    /// with runtime values outside SwiftUI.
    static func format(_ key: String, defaultValue: String, locale: Locale? = nil, _ arguments: CVarArg...) -> String {
        let resolvedLocale = locale ?? currentLanguage.locale
        let template = text(key, defaultValue: defaultValue, locale: resolvedLocale)
        return String(format: template, locale: resolvedLocale, arguments: arguments)
    }

    /// Exposed so tests can confirm the `.lproj` resource layout without
    /// reaching into `Bundle.module` directly.
    static func resourcePath(
        forLocalization localization: String,
        resource: String = "Localizable",
        type: String = "strings"
    ) -> String? {
        Bundle.module.path(forResource: resource, ofType: type, inDirectory: nil, forLocalization: localization)
    }

    private static func bundle(for locale: Locale) -> Bundle {
        // SwiftPM lowercases `.lproj` directory names on disk (e.g.
        // `zh-Hans.lproj` → `zh-hans.lproj`), so we probe a few variants of
        // the locale identifier before falling back to the module bundle.
        let candidates: [String] = {
            var out: [String] = []
            if let id = Optional(locale.identifier), !id.isEmpty {
                out.append(id)
                out.append(id.lowercased())
            }
            if let lang = locale.language.languageCode?.identifier {
                out.append(lang)
                out.append(lang.lowercased())
            }
            return out
        }()

        for identifier in candidates {
            let resolved = bundleCache.bundle(for: identifier) {
                if let path = Bundle.module.path(forResource: identifier, ofType: "lproj"),
                   let b = Bundle(path: path) {
                    return b
                }
                return .module
            }
            if resolved !== Bundle.module { return resolved }
        }
        return .module
    }
}
