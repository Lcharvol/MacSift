import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var exclusionManager = ExclusionManager()
    @StateObject private var updateVM = UpdateViewModel()
    @StateObject private var menuBarVM = MenuBarViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(exclusionManager: exclusionManager, appState: appState)
                .environmentObject(appState)
                .environmentObject(exclusionManager)
                .environmentObject(updateVM)
                .frame(minWidth: 900, minHeight: 650)
                .task {
                    // Silent update check on launch, throttled to 24h by
                    // the view model itself. Failures are swallowed —
                    // the banner just stays hidden.
                    await updateVM.checkForUpdateIfNeeded()
                }
        }

        // Menu bar widget — live disk / memory / CPU metrics plus quick
        // actions. NOTE: we deliberately do NOT bind `isInserted:` to a
        // @Published property — doing so produced an infinite rebuild
        // loop on macOS 26 where SwiftUI's MenuBarExtraHost kept calling
        // `requestUpdate` every frame, pegging a core at 100% and
        // starving the main thread (main window never rendered, menu
        // bar icon never appeared). The scene is always inserted; the
        // user can hide the status item via menu bar settings if they
        // really don't want it.
        MenuBarExtra {
            MenuBarContent(menuBarVM: menuBarVM)
                .environmentObject(appState)
        } label: {
            Image(systemName: "externaldrive.badge.checkmark")
        }
        .menuBarExtraStyle(.window)
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            // Custom About panel
            CommandGroup(replacing: .appInfo) {
                Button("About MacSift") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "MacSift",
                        .applicationVersion: version,
                        .credits: NSAttributedString(
                            string: "Transparent macOS disk cleaning utility.\nMoves files to the Trash — never deletes permanently.",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor.secondaryLabelColor,
                            ]
                        ),
                    ])
                }
                Button("Check for Updates…") {
                    Task { await updateVM.checkForUpdateIfNeeded(force: true) }
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
