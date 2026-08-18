import SwiftUI

struct ContentView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Фоновый градиент
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.25),
                    Color(red: 0.08, green: 0.12, blue: 0.22)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("TG WS Proxy")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(proxyManager.isRunning ? "● Активен" : "● Остановлен")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(proxyManager.isRunning ? .green : .gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.15, opacity: 0.6),
                            Color(white: 0.1, opacity: 0.4)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Вкладки
                HStack(spacing: 0) {
                    TabBarItem(
                        icon: "wifi",
                        title: "Proxy",
                        isSelected: selectedTab == 0,
                        action: { selectedTab = 0 }
                    )
                    
                    TabBarItem(
                        icon: "gear",
                        title: "Settings",
                        isSelected: selectedTab == 1,
                        action: { selectedTab = 1 }
                    )
                    
                    TabBarItem(
                        icon: "doc.text",
                        title: "Logs",
                        isSelected: selectedTab == 2,
                        action: { selectedTab = 2 }
                    )
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.12, opacity: 0.8),
                            Color(white: 0.08, opacity: 0.6)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 1)
                
                // Содержание вкладок
                TabView(selection: $selectedTab) {
                    ProxyTabView()
                        .tag(0)
                    
                    SettingsTabView()
                        .tag(1)
                    
                    LogsTabView()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(isSelected ? .cyan : .gray)
            .background(
                isSelected ?
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.cyan.opacity(0.3),
                        Color.blue.opacity(0.2)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ) : LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                isSelected ?
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.cyan.opacity(0.5),
                                Color.blue.opacity(0.3)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    ) : nil
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProxyManager())
}
