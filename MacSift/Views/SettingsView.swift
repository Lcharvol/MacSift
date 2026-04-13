import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var exclusionManager: ExclusionManager

    /// Track the threshold at view appear so we can show a "Rescan to apply"
    /// hint if the user changes it mid-session.
    @State private var initialThresholdMB: Int = 0
    @State private var didLoadInitial = false

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
                        Button("All suggested") {
                            addDefaultExclusions(includeAll: true)
                        }
                        Divider()
                        ForEach(defaultSuggestions, id: \.url) { suggestion in
                            Button(suggestion.label) {
                                exclusionManager.addExclusion(suggestion.url)
                            }
                        }
                    } label: {
                        Label("Suggested…", systemImage: "wand.and.stars")
                    }
                    .menuStyle(.borderlessButton)
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
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
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

    private func addDefaultExclusions(includeAll: Bool) {
        for s in defaultSuggestions {
            exclusionManager.addExclusion(s.url)
        }
    }
}
