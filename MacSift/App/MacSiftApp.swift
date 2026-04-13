import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var exclusionManager = ExclusionManager()

    var body: some Scene {
        WindowGroup {
            MainView(exclusionManager: exclusionManager, appState: appState)
                .environmentObject(appState)
                .environmentObject(exclusionManager)
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            // Custom About panel
            CommandGroup(replacing: .appInfo) {
                Button("About MacSift") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "MacSift",
                        .applicationVersion: "0.1.0",
                        .credits: NSAttributedString(
                            string: "Transparent macOS disk cleaning utility.\nMoves files to the Trash — never deletes permanently.",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor.secondaryLabelColor,
                            ]
                        ),
                    ])
                }
            }

            // File menu commands with keyboard shortcuts
            CommandGroup(after: .newItem) {
                Button("Scan Now") {
                    NotificationCenter.default.post(name: .macSiftStartScan, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Cancel Scan") {
                    NotificationCenter.default.post(name: .macSiftCancelScan, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Select All Safe") {
                    NotificationCenter.default.post(name: .macSiftSelectAllSafe, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    NotificationCenter.default.post(name: .macSiftDeselectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(exclusionManager: exclusionManager)
                .environmentObject(appState)
        }
    }
}

extension Notification.Name {
    static let macSiftStartScan = Notification.Name("MacSift.StartScan")
    static let macSiftCancelScan = Notification.Name("MacSift.CancelScan")
    static let macSiftSelectAllSafe = Notification.Name("MacSift.SelectAllSafe")
    static let macSiftDeselectAll = Notification.Name("MacSift.DeselectAll")
}
