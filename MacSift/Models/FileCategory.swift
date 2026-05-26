import SwiftUI

enum RiskLevel: String, CaseIterable, Sendable {
    case safe
    case moderate
    case risky

    var color: Color {
        switch self {
        case .safe: .green
        case .moderate: .orange
        case .risky: .red
        }
    }

    var label: String {
        localizedLabel()
    }

    func localizedLabel(locale: Locale = .current) -> String {
        switch self {
        case .safe: L10n.text("risk.safe", defaultValue: "Safe to delete", locale: locale)
        case .moderate: L10n.text("risk.moderate", defaultValue: "Review recommended", locale: locale)
        case .risky: L10n.text("risk.risky", defaultValue: "Use caution", locale: locale)
        }
    }
}

enum FileCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case cache
    case logs
    case tempFiles
    case appData
    case largeFiles
    case timeMachineSnapshots
    case iosBackups
    case xcodeJunk
    case devCaches
    case oldDownloads
    case mailDownloads

    var id: String { rawValue }

    var label: String {
        localizedLabel()
    }

    func localizedLabel(locale: Locale = .current) -> String {
        switch self {
        case .cache: L10n.text("category.cache", defaultValue: "Caches", locale: locale)
        case .logs: L10n.text("category.logs", defaultValue: "Logs", locale: locale)
        case .tempFiles: L10n.text("category.tempFiles", defaultValue: "Temporary Files", locale: locale)
        case .appData: L10n.text("category.appData", defaultValue: "Unused App Data", locale: locale)
        case .largeFiles: L10n.text("category.largeFiles", defaultValue: "Large Files", locale: locale)
        case .timeMachineSnapshots: L10n.text("category.timeMachineSnapshots", defaultValue: "Time Machine Snapshots", locale: locale)
        case .iosBackups: L10n.text("category.iosBackups", defaultValue: "iOS Backups", locale: locale)
        case .xcodeJunk: L10n.text("category.xcodeJunk", defaultValue: "Xcode Junk", locale: locale)
        case .devCaches: L10n.text("category.devCaches", defaultValue: "Dev Caches", locale: locale)
        case .oldDownloads: L10n.text("category.oldDownloads", defaultValue: "Old Downloads", locale: locale)
        case .mailDownloads: L10n.text("category.mailDownloads", defaultValue: "Mail Attachments", locale: locale)
        }
    }

    var iconName: String {
        switch self {
        case .cache: "folder.badge.gearshape"
        case .logs: "doc.text"
        case .tempFiles: "tray.full"
        case .appData: "app.dashed"
        case .largeFiles: "externaldrive"
        case .timeMachineSnapshots: "clock.arrow.circlepath"
        case .iosBackups: "iphone"
        case .xcodeJunk: "hammer"
        case .devCaches: "shippingbox"
        case .oldDownloads: "tray.and.arrow.down"
        case .mailDownloads: "paperclip"
        }
    }

    var riskLevel: RiskLevel {
        switch self {
        case .cache, .logs, .tempFiles, .xcodeJunk, .devCaches: .safe
        case .appData, .timeMachineSnapshots, .mailDownloads: .moderate
        case .largeFiles, .iosBackups, .oldDownloads: .risky
        }
    }

    var displayColor: Color {
        switch self {
        case .cache: .blue
        case .logs: .gray
        case .tempFiles: .cyan
        case .appData: .purple
        case .largeFiles: .orange
        case .timeMachineSnapshots: .green
        case .iosBackups: .pink
        case .xcodeJunk: .indigo
        case .devCaches: .mint
        case .oldDownloads: .brown
        case .mailDownloads: .teal
        }
    }
}
