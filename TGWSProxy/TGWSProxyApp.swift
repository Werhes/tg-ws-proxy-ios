import SwiftUI

@main
struct TGWSProxyApp: App {
    @StateObject private var proxyManager = ProxyManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proxyManager)
        }
    }
}
