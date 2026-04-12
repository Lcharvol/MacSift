import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var exclusionManager: ExclusionManager

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
            }

            Section("Excluded Folders") {
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
        .frame(width: 450, height: 400)
    }
}
