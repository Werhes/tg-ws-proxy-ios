import SwiftUI

struct ProxyTabView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @State private var showCopyAlert = false
    @State private var showConnectAlert = false
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Статус прокси
                    GlassCard {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Статус")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Circle()
                                    .fill(proxyManager.isRunning ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: proxyManager.isRunning ? Color.green.opacity(0.5) : Color.red.opacity(0.5), radius: 4)
                            }
                            
                            Text(proxyManager.isRunning ? "Прокси активен" : "Прокси остановлен")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Информация о хосте и порте
                    GlassCard {
                        VStack(spacing: 12) {
                            InfoRow(label: "Хост", value: proxyManager.host)
                            Divider().background(Color.white.opacity(0.1))
                            InfoRow(label: "Порт", value: String(proxyManager.port))
                            Divider().background(Color.white.opacity(0.1))
                            InfoRow(label: "Secret", value: proxyManager.secret.count > 0 ? "●●●●●●●●" : "Не установлен")
                        }
                    }
                    
                    // Ссылка на подключение
                    GlassCard {
                        VStack(spacing: 12) {
                            Text("Ссылка для подключения")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 8) {
                                Text(proxyManager.proxyLink)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.cyan)
                                    .lineLimit(2)
                                
                                Spacer()
                                
                                Button(action: { copyLink() }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 14))
                                        .foregroundColor(.cyan)
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                    
                    // Кнопки действий
                    HStack(spacing: 12) {
                        Button(action: { toggleProxy() }) {
                            HStack(spacing: 6) {
                                Image(systemName: proxyManager.isRunning ? "stop.circle" : "play.circle")
                                    .font(.system(size: 16))
                                
                                Text(proxyManager.isRunning ? "Остановить" : "Запустить")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        proxyManager.isRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8),
                                        proxyManager.isRunning ? Color.red.opacity(0.6) : Color.green.opacity(0.6)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(8)
                        }
                        
                        Button(action: { openInTelegram() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                
                                Text("Telegram")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.2, green: 0.6, blue: 0.95).opacity(0.8),
                                        Color(red: 0.1, green: 0.5, blue: 0.85).opacity(0.6)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(8)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .alert("Скопировано", isPresented: $showCopyAlert) {
            Button("OK") { }
        } message: {
            Text("Ссылка скопирована в буфер обмена")
        }
    }
    
    private func copyLink() {
        UIPasteboard.general.string = proxyManager.proxyLink
        showCopyAlert = true
    }
    
    private func toggleProxy() {
        proxyManager.toggleProxy()
    }
    
    private func openInTelegram() {
        let telegramScheme = "tg://"
        if let url = URL(string: proxyManager.proxyLink),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.cyan)
        }
    }
}

#Preview {
    ProxyTabView()
        .environmentObject(ProxyManager())
}
