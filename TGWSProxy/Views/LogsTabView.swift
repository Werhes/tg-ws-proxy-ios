import SwiftUI

struct LogsTabView: View {
    @EnvironmentObject var proxyManager: ProxyManager
    @State private var autoScroll = true
    @State private var selectedLogLevel = "All"
    let logLevels = ["All", "Info", "Warning", "Error"]
    
    var filteredLogs: [LogEntry] {
        if selectedLogLevel == "All" {
            return proxyManager.logs
        }
        return proxyManager.logs.filter { $0.level == selectedLogLevel }
    }
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Фильтры и кнопки
                HStack(spacing: 12) {
                    Picker("Уровень", selection: $selectedLogLevel) {
                        ForEach(logLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.cyan)
                    
                    Button(action: clearLogs) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                }
                .padding(12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.12, opacity: 0.5),
                            Color(white: 0.08, opacity: 0.4)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(8)
                .padding(12)
                
                // Лог
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if filteredLogs.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                        
                                        Text("Логи отсутствуют")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(.vertical, 40)
                                    Spacer()
                                }
                            } else {
                                ForEach(filteredLogs) { log in
                                    LogRow(log: log)
                                        .id(log.id)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: filteredLogs.count) { _ in
                        if autoScroll, let lastLog = filteredLogs.last {
                            reader.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
    
    private func clearLogs() {
        proxyManager.clearLogs()
    }
}

struct LogRow: View {
    let log: LogEntry
    
    var levelColor: Color {
        switch log.level {
        case "Info":
            return Color.cyan
        case "Warning":
            return Color.yellow
        case "Error":
            return Color.red
        default:
            return Color.gray
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(levelColor)
                        .frame(width: 6, height: 6)
                    
                    Text(log.level)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(levelColor)
                    
                    Text(log.timestamp)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                Text(log.message)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(nil)
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .cornerRadius(6)
        }
    }
}

#Preview {
    LogsTabView()
        .environmentObject(ProxyManager())
}
