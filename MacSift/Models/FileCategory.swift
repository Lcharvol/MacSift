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
        switch self {
        case .safe: String(localized: "risk.safe", defaultValue: "Safe to delete")
        case .moderate: String(localized: "risk.moderate", defaultValue: "Review recommended")
        case .risky: String(localized: "risk.risky", defaultValue: "Use caution")
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
        switch self {
        case .cache: String(localized: "category.cache", defaultValue: "Caches")
        case .logs: String(localized: "category.logs", defaultValue: "Logs")
        case .tempFiles: String(localized: "category.tempFiles", defaultValue: "Temporary Files")
        case .appData: String(localized: "category.appData", defaultValue: "Unused App Data")
        case .largeFiles: String(localized: "category.largeFiles", defaultValue: "Large Files")
        case .timeMachineSnapshots: String(localized: "category.timeMachineSnapshots", defaultValue: "Time Machine Snapshots")
        case .iosBackups: String(localized: "category.iosBackups", defaultValue: "iOS Backups")
        case .xcodeJunk: String(localized: "category.xcodeJunk", defaultValue: "Xcode Junk")
        case .devCaches: String(localized: "category.devCaches", defaultValue: "Dev Caches")
        case .oldDownloads: String(localized: "category.oldDownloads", defaultValue: "Old Downloads")
        case .mailDownloads: String(localized: "category.mailDownloads", defaultValue: "Mail Attachments")
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
