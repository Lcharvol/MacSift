import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var exclusionManager: ExclusionManager

    /// Track the threshold at view appear so we can show a "Rescan to apply"
    /// hint if the user changes it mid-session.
    @State private var initialThresholdMB: Int = 0
    @State private var didLoadInitial = false
    @State private var showResetConfirmation = false
    @State private var showUninstallConfirmation = false
    @State private var uninstallReport: UninstallService.Report?
    @State private var showUninstallResult = false

    private var thresholdChanged: Bool {
        didLoadInitial && initialThresholdMB != appState.largeFileThresholdMB
    }

    var body: some View {
        Form {
            Section("General") {
                Picker("Mode", selection: $appState.mode) {
                    Text("Simple").tag(AppState.Mode.simple)
                    Text("Advanced").tag(AppState.Mode.advanced)
                }

                Toggle("Dry Run (simulate deletions)", isOn: $appState.isDryRun)

                HStack {
                    Text("Large file threshold")
                    Spacer()
                    TextField("MB", value: $appState.largeFileThresholdMB, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("MB")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Old Downloads threshold")
                    Spacer()
                    TextField("days", value: $appState.oldDownloadsAgeDays, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("days")
                        .foregroundStyle(.secondary)
                }

                if thresholdChanged {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.orange)
                        Text("Rescan to apply the new threshold.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Excluded Folders") {
                if exclusionManager.excludedPaths.isEmpty {
                    Text("No folders are excluded from scans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(exclusionManager.excludedPaths, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            Text(url.path(percentEncoded: false))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                exclusionManager.removeExclusion(url)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false

                        if panel.runModal() == .OK, let url = panel.url {
                            exclusionManager.addExclusion(url)
                        }
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                    }

                    Spacer()

                    Menu {
                        let allAdded = defaultSuggestions.allSatisfy { exclusionManager.isExcluded($0.url) }
                        Button("Add all") {
                            addDefaultExclusions()
                        }
                        .disabled(allAdded)
                        Divider()
                        ForEach(defaultSuggestions, id: \.url) { suggestion in
                            let alreadyAdded = exclusionManager.isExcluded(suggestion.url)
                            Button {
                                exclusionManager.addExclusion(suggestion.url)
                            } label: {
                                if alreadyAdded {
                                    Label(suggestion.label, systemImage: "checkmark")
                                } else {
                                    Text(suggestion.label)
                                }
                            }
                            .disabled(alreadyAdded)
                        }
                    } label: {
                        Label("Suggested…", systemImage: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            Section("Stats") {
                HStack {
                    Text("Scans run")
                    Spacer()
                    Text("\(appState.lifetimeScanCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Total cleaned")
                    Spacer()
                    Text(appState.lifetimeCleanedBytes.formattedFileSize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Full Disk Access")
                    Spacer()
                    if FullDiskAccess.check() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            FullDiskAccess.openSystemSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset all settings")
                            .font(.callout.weight(.medium))
                        Text("Clears mode, dry-run, threshold, and all excluded folders.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset…", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .controlSize(.small)
                }
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uninstall MacSift")
                            .font(.callout.weight(.medium))
                        Text("Erases settings, audit log, downloaded updates, and moves MacSift.app to the Trash.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Uninstall…", role: .destructive) {
                        showUninstallConfirmation = true
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 500)
        .alert("Reset all MacSift settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This clears your mode, dry-run preference, large file threshold, and the list of excluded folders. Your files on disk are not touched.")
        }
        .alert("Uninstall MacSift?", isPresented: $showUninstallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                Task { await performUninstall() }
            }
        } message: {
            Text("""
This will:

• Erase all MacSift settings and excluded folders
• Delete the audit log at ~/Library/Logs/MacSift
• Remove any downloaded update zips from ~/Downloads
• Move MacSift.app itself to the Trash

MacSift will quit immediately after. Your scanned files and anything else on disk stay exactly where they are — only MacSift's own data is removed.

You'll still need to revoke Full Disk Access manually in System Settings if you want it fully gone.
""")
        }
        .alert("MacSift uninstalled", isPresented: $showUninstallResult) {
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } message: {
            if let report = uninstallReport {
                Text(uninstallSummaryText(for: report))
            } else {
                Text("Done.")
            }
        }
        .onAppear {
            if !didLoadInitial {
                initialThresholdMB = appState.largeFileThresholdMB
                didLoadInitial = true
            }
        }
    }

    private struct DefaultExclusion {
        let label: String
        let url: URL
    }

    private var defaultSuggestions: [DefaultExclusion] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            DefaultExclusion(label: "Music", url: home.appending(path: "Music")),
            DefaultExclusion(label: "Pictures", url: home.appending(path: "Pictures")),
            DefaultExclusion(label: "Movies", url: home.appending(path: "Movies")),
            DefaultExclusion(label: "iOS Backups (MobileSync)", url: home.appending(path: "Library/Application Support/MobileSync")),
        ]
    }

    private func addDefaultExclusions() {
        for s in defaultSuggestions {
            exclusionManager.addExclusion(s.url)
        }
    }

    /// Run the full uninstall pipeline and present a summary alert. The
    /// summary alert's single "Quit" button actually terminates the app
    /// — by the time we get here the running bundle is already in the
    /// Trash, so there's nothing to keep alive.
    private func performUninstall() async {
        let report = await UninstallService.uninstall()
        MacSiftLog.info("Uninstall complete: clearedDefaults=\(report.clearedUserDefaults) " +
            "logsRemoved=\(report.removedLogsAt != nil) " +
            "updateArtifacts=\(report.removedUpdateArtifacts) " +
            "bundleTrashed=\(report.trashedBundleAt != nil)")
        uninstallReport = report
        showUninstallResult = true
    }

    private func uninstallSummaryText(for report: UninstallService.Report) -> String {
        var lines: [String] = []
        if report.clearedUserDefaults {
            lines.append("✓ Settings and exclusions erased")
        }
        if report.removedLogsAt != nil {
            lines.append("✓ Audit log removed")
        }
        if report.removedUpdateArtifacts > 0 {
            let size = report.reclaimedUpdateBytes.formattedFileSize
            lines.append("✓ Removed \(report.removedUpdateArtifacts) cached update artifact(s) (\(size))")
        }
        if report.trashedBundleAt != nil {
            lines.append("✓ MacSift.app moved to Trash")
        }
        if !report.errors.isEmpty {
            lines.append("")
            lines.append("Partial failures:")
            for err in report.errors {
                lines.append("• \(err)")
            }
        }
        lines.append("")
        lines.append("Thanks for trying MacSift. Click Quit to exit.")
        return lines.joined(separator: "\n")
    }

    private func resetAllSettings() {
        // Setting each @Published property triggers its didSet which writes
        // the default value back to UserDefaults — no need to removeObject
        // first (that was redundant and only fired didSet a second time).
        appState.mode = .simple
        appState.isDryRun = true
        appState.largeFileThresholdMB = 500
        appState.oldDownloadsAgeDays = 90
        appState.lifetimeScanCount = 0
        appState.lifetimeCleanedBytes = 0
        // Clear exclusions — persisted via ExclusionManager's own storage.
        for url in exclusionManager.excludedPaths {
            exclusionManager.removeExclusion(url)
        }
    }
}
