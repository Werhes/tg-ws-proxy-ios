import SwiftUI

@main
struct TGWSProxyApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .task {
                    // Ensure the proxy domain refresh starts on launch
                    appState.proxyManager.bootstrap()
                }
        }
    }
}