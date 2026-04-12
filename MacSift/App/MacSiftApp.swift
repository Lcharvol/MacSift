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

        Settings {
            SettingsView(exclusionManager: exclusionManager)
                .environmentObject(appState)
        }
    }
}
