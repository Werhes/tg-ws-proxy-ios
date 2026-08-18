import Foundation
import Combine

class ProxyManager: ObservableObject {
    @Published var isRunning = false
    @Published var host = "127.0.0.1"
    @Published var port = 8080
    @Published var secret = ""
    @Published var logs: [LogEntry] = []
    
    private var proxyProcess: Process?
    private let logQueue = DispatchQueue(label: "com.tgwsproxy.logs")
    
    var proxyLink: String {
        let scheme = secret.isEmpty ? "tg-proxy" : "tg-socks"
        return "\(scheme)://\(host):\(port)" + (secret.isEmpty ? "" : "?secret=\(secret)")
    }
    
    init() {
        loadSettings()
        addMockLogs()
    }
    
    func toggleProxy() {
        if isRunning {
            stopProxy()
        } else {
            startProxy()
        }
    }
    
    func startProxy() {
        DispatchQueue.main.async {
            self.isRunning = true
            self.addLog("Прокси запущен", level: "Info")
            self.addLog("Слушаю на \(self.host):\(self.port)", level: "Info")
        }
        
        // Симуляция работы прокси
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.addLog("Соединение установлено", level: "Info")
            self.addLog("Готов к подключениям", level: "Info")
        }
    }
    
    func stopProxy() {
        DispatchQueue.main.async {
            self.isRunning = false
            self.addLog("Прокси остановлен", level: "Info")
        }
    }
    
    func updateSettings(host: String, port: Int, secret: String) {
        DispatchQueue.main.async {
            self.host = host
            self.port = port
            self.secret = secret
            self.saveSettings()
            self.addLog("Настройки обновлены", level: "Info")
        }
    }
    
    func addLog(_ message: String, level: String = "Info") {
        logQueue.async { [weak self] in
            let timestamp = Self.formatTime(Date())
            let entry = LogEntry(
                level: level,
                message: message,
                timestamp: timestamp
            )
            
            DispatchQueue.main.async {
                self?.logs.append(entry)
                // Сохранять максимум 1000 логов
                if self?.logs.count ?? 0 > 1000 {
                    self?.logs.removeFirst()
                }
            }
        }
    }
    
    func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.addLog("Логи очищены", level: "Info")
        }
    }
    
    private func saveSettings() {
        let settings: [String: Any] = [
            "host": host,
            "port": port,
            "secret": secret
        ]
        UserDefaults.standard.setValue(settings, forKey: "ProxySettings")
    }
    
    private func loadSettings() {
        if let settings = UserDefaults.standard.dictionary(forKey: "ProxySettings") {
            if let host = settings["host"] as? String {
                self.host = host
            }
            if let port = settings["port"] as? Int {
                self.port = port
            }
            if let secret = settings["secret"] as? String {
                self.secret = secret
            }
        }
    }
    
    private func addMockLogs() {
        addLog("Приложение запущено", level: "Info")
        addLog("Конфигурация загружена", level: "Info")
        addLog("Ожидание команды запуска...", level: "Info")
    }
    
    private static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let level: String
    let message: String
    let timestamp: String
}
