import SwiftUI

@main
struct TGWSProxyApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                // Keep the app's font small regardless of the system
                // Dynamic Type / text-size setting (max system font still small).
                .environment(\.dynamicTypeSize, .xSmall)
                .task {
                    // Ensure the proxy domain refresh starts on launch
                    appState.proxyManager.bootstrap()
                }
        }
    }
}