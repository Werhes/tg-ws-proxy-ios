import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @State private var editHost = ""
    @State private var editPort = ""
    @State private var editSecret = ""
    @State private var showSaveAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Общие настройки
                    SectionHeader(title: "Основные параметры")
                    
                    GlassCard {
                        VStack(spacing: 16) {
                            SettingTextField(
                                label: "Хост",
                                text: $editHost,
                                placeholder: "127.0.0.1"
                            )
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            SettingTextField(
                                label: "Порт",
                                text: $editPort,
                                placeholder: "8080",
                                keyboardType: .numberPad
                            )
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            SettingTextField(
                                label: "Secret Key",
                                text: $editSecret,
                                placeholder: "Оставить пустым",
                                isSecure: true
                            )
                        }
                    }
                    
                    // Дополнительные настройки
                    SectionHeader(title: "Дополнительно")
                    
                    GlassCard {
                        VStack(spacing: 12) {
                            Toggle(isOn: .constant(true)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.cyan)
                                    
                                    Text("Автозапуск при открытии")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .tint(.cyan)
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            Toggle(isOn: .constant(false)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.cyan)
                                    
                                    Text("Уведомления об ошибках")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .tint(.cyan)
                        }
                    }
                    
                    // О приложении
                    SectionHeader(title: "О приложении")
                    
                    GlassCard {
                        VStack(spacing: 12) {
                            InfoRow(label: "Версия", value: "1.0.0")
                            Divider().background(Color.white.opacity(0.1))
                            InfoRow(label: "Автор", value: "Flowseal")
                            Divider().background(Color.white.opacity(0.1))
                            InfoRow(label: "Лицензия", value: "MIT")
                        }
                    }
                    
                    // Кнопка сохранения
                    Button(action: saveSettings) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                            
                            Text("Сохранить изменения")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.cyan.opacity(0.8),
                                    Color.blue.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                    }
                    .padding(.top, 12)
                    
                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .onAppear {
            editHost = proxyManager.host
            editPort = String(proxyManager.port)
            editSecret = proxyManager.secret
        }
        .alert("Настройки", isPresented: $showSaveAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveSettings() {
        guard !editHost.isEmpty else {
            alertMessage = "Укажите хост"
            showSaveAlert = true
            return
        }
        
        guard let port = Int(editPort), port > 0, port < 65536 else {
            alertMessage = "Укажите правильный порт (1-65535)"
            showSaveAlert = true
            return
        }
        
        proxyManager.updateSettings(
            host: editHost,
            port: port,
            secret: editSecret
        )
        
        alertMessage = "Настройки сохранены"
        showSaveAlert = true
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }
}

struct SettingTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.cyan)
                    .keyboardType(keyboardType)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.cyan)
                    .keyboardType(keyboardType)
            }
        }
    }
}

#Preview {
    SettingsTabView()
        .environmentObject(ProxyManager())
}
