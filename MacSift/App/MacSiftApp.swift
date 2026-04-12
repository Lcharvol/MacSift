import SwiftUI

@main
struct MacSiftApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
    }
}

struct ContentView: View {
    var body: some View {
        Text("MacSift")
            .font(.largeTitle)
    }
}
