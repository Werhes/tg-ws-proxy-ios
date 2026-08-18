import SwiftUI
import UIKit

/// The main control tab: shows proxy status, start/stop control,
/// the connection link, and live traffic statistics.
struct ProxyTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                statsCard
                linkCard
                aboutCard
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Status

    private var statusCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Telegram logo badge (like the Android app's hero icon).
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.55), Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)
                        .shadow(color: Color.blue.opacity(0.6), radius: 22, x: 0, y: 6)

                    TelegramLogo()
                        .frame(width: 52, height: 52)

                    Circle()
                        .stroke(
                            appState.proxyManager.isListening ? Color.green : Color.red,
                            lineWidth: 3
                        )
                        .frame(width: 92, height: 92)
                        .opacity(0.9)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appState.proxyManager.isListening)

                Text(appState.proxyManager.isListening ? "Прокси запущен" : "Прокси остановлен")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)

                Text("\(appState.proxyManager.settings.host):\(String(appState.proxyManager.settings.port))")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                Button {
                    appState.proxyManager.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: appState.proxyManager.isListening ? "stop.fill" : "play.fill")
                        Text(appState.proxyManager.isListening ? "Остановить" : "Запустить")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                appState.proxyManager.isListening
                                    ? AnyShapeStyle(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                            )
                            .shadow(color: (appState.proxyManager.isListening ? Color.red : Color.blue).opacity(0.4), radius: 10, x: 0, y: 5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(appState.proxyManager.status == .starting || appState.proxyManager.status == .stopping)

                if let errorText = errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var errorText: String? {
        switch appState.proxyManager.status {
        case .error(let message):
            return message
        default:
            return nil
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                label("Статистика", icon: "chart.bar.fill")

                HStack(spacing: 12) {
                    statItem(title: "Активные", value: "\(appState.activeConnections)", icon: "link.circle.fill", color: .cyan)
                    statItem(title: "WebSocket", value: "\(appState.wsConnections)", icon: "globe.americas.fill", color: .blue)
                }
                HStack(spacing: 12) {
                    statItem(title: "Загрузка", value: humanBytes(appState.bytesUp), icon: "arrow.up.circle.fill", color: .green)
                    statItem(title: "Скачано", value: humanBytes(appState.bytesDown), icon: "arrow.down.circle.fill", color: .teal)
                }
            }
        }
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Link

    private var linkCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                label("Ссылка подключения", icon: "link")

                Text(appState.proxyManager.connectionLink)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = appState.proxyManager.connectionLink
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Скопировано" : "Копировать")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    if let url = URL(string: appState.proxyManager.connectionLink) {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("Открыть в Telegram")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.cyan.opacity(0.35)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                label("О приложении", icon: "info.circle")

                Text("TG WS Proxy — нативный прокси для Telegram, работающий через WebSocket (MTProto). Проект переписан с Python на Swift.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func label(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(text)
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    private func humanBytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var v = Double(value)
        var index = 0
        while abs(v) >= 1024 && index < units.count - 1 {
            v /= 1024
            index += 1
        }
        return String(format: "%.1f%@", v, units[index])
    }
}