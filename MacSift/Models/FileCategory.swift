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
        case .safe: "Safe to delete"
        case .moderate: "Review recommended"
        case .risky: "Use caution"
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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cache: "Caches"
        case .logs: "Logs"
        case .tempFiles: "Temporary Files"
        case .appData: "Unused App Data"
        case .largeFiles: "Large Files"
        case .timeMachineSnapshots: "Time Machine Snapshots"
        case .iosBackups: "iOS Backups"
        }
    }

    var iconName: String {
        switch self {
        case .cache: "folder.badge.gearshape"
        case .logs: "doc.text"
        case .tempFiles: "clock.arrow.circlepath"
        case .appData: "app.dashed"
        case .largeFiles: "externaldrive"
        case .timeMachineSnapshots: "timemachine"
        case .iosBackups: "iphone"
        }
    }

    var riskLevel: RiskLevel {
        switch self {
        case .cache, .logs, .tempFiles: .safe
        case .appData, .timeMachineSnapshots: .moderate
        case .largeFiles, .iosBackups: .risky
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
        }
    }
}
