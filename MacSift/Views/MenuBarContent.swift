import SwiftUI
import AppKit

/// Compact popover shown when the user clicks MacSift's menu bar icon.
/// Three stat cards (Disk / Memory / CPU) plus quick actions for
/// opening the main window and starting a scan.
struct MenuBarContent: View {
    @ObservedObject var menuBarVM: MenuBarViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider().opacity(0.5)

            VStack(spacing: 10) {
                metricRow(
                    icon: "internaldrive",
                    tint: .blue,
                    label: "Startup disk",
                    primary: "\(menuBarVM.metrics.diskFree.formattedFileSize) free",
                    secondary: "\(menuBarVM.metrics.diskTotal.formattedFileSize) total",
                    fraction: menuBarVM.metrics.diskUsedFraction
                )

                metricRow(
                    icon: "memorychip",
                    tint: .green,
                    label: "Memory",
                    primary: "\(menuBarVM.metrics.memoryUsed.formattedFileSize) used",
                    secondary: "\(menuBarVM.metrics.memoryTotal.formattedFileSize) total",
                    fraction: menuBarVM.metrics.memoryUsedFraction
                )

                metricRow(
                    icon: "cpu",
                    tint: cpuTint,
                    label: "CPU",
                    primary: cpuLabel,
                    secondary: thermalLabel,
                    fraction: menuBarVM.metrics.cpuLoad
                )
            }

            Divider().opacity(0.5)

            quickActions

            Divider().opacity(0.5)

            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { menuBarVM.setPopoverVisible(true) }
        .onDisappear { menuBarVM.setPopoverVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            Text("MacSift")
                .font(.callout.weight(.semibold))
            Spacer()
            if appState.lifetimeCleanedBytes > 0 {
                Text("\(appState.lifetimeCleanedBytes.formattedFileSize) cleaned")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func metricRow(
        icon: String,
        tint: Color,
        label: String,
        primary: String,
        secondary: String,
        fraction: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(primary)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(tint)
        }
    }

    private var quickActions: some View {
        VStack(spacing: 6) {
            Button {
                openMainWindow()
            } label: {
                Label("Open MacSift", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quinary)
            )

            Button {
                openMainWindow()
                NotificationCenter.default.post(name: .macSiftStartScan, object: nil)
            } label: {
                Label("Scan now", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quinary)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    private var cpuTint: Color {
        let load = menuBarVM.metrics.cpuLoad
        if load > 0.8 { return .red }
        if load > 0.5 { return .orange }
        return .green
    }

    private var cpuLabel: String {
        "\(Int(menuBarVM.metrics.cpuLoad * 100))% used"
    }

    private var thermalLabel: String {
        switch menuBarVM.metrics.thermalState {
        case .nominal: return String(localized: "Thermal: nominal")
        case .fair: return String(localized: "Thermal: fair")
        case .serious: return String(localized: "Thermal: serious")
        case .critical: return String(localized: "Thermal: critical")
        @unknown default: return String(localized: "Thermal: unknown")
        }
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Bring the existing main window forward, or create one if the
        // WindowGroup is empty (user closed the last window earlier).
        if let window = NSApp.windows.first(where: { $0.title.contains("MacSift") || $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
        }
    }
}
