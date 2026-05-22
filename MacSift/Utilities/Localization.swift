import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese
    case french

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .french: "fr"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier ?? Locale.current.identifier)
    }

    var displayName: String {
        switch self {
        case .system:
            L10n.text("language.system", defaultValue: "System")
        case .english:
            L10n.text("language.english", defaultValue: "English")
        case .simplifiedChinese:
            L10n.text("language.simplifiedChinese", defaultValue: "Simplified Chinese")
        case .french:
            L10n.text("language.french", defaultValue: "French")
        }
    }
}

enum L10n {
    private static let languageKey = "appLanguage"

    private static var currentLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: languageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static var currentLocale: Locale {
        currentLanguage.locale
    }

    static func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: languageKey)
    }

    private static func bundle(for locale: Locale) -> Bundle {
        let identifiers = [
            locale.identifier,
            locale.language.languageCode?.identifier,
        ].compactMap { $0 }

        for identifier in identifiers {
            if let path = Bundle.module.path(forResource: identifier, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .module
    }

    static func resourcePath(
        forLocalization localization: String,
        resource: String = "Localizable",
        type: String = "strings"
    ) -> String? {
        Bundle.module.path(
            forResource: resource,
            ofType: type,
            inDirectory: nil,
            forLocalization: localization
        )
    }

    static func text(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil
    ) -> String {
        let resolvedLocale = locale ?? currentLocale
        let localized = bundle(for: resolvedLocale).localizedString(forKey: key, value: defaultValue, table: nil)
        return localized == key ? defaultValue : localized
    }

    static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let resolvedLocale = locale ?? currentLocale
        let template = text(key, defaultValue: defaultValue, locale: resolvedLocale)
        return String(format: template, locale: resolvedLocale, arguments: arguments)
    }
}
