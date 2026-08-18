import SwiftUI
import UIKit

/// The settings tab: host, port, secret, fake-TLS domain, and toggle options.
struct SettingsTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var secret: String = ""
    @State private var fakeTLS: String = ""
    @State private var fallbackCF: Bool = true
    @State private var proxyProtocol: Bool = false
    @State private var forceTestDC: Bool = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionCard
                togglesCard
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: loadFromSettings)
    }

    // MARK: - Connection

    private var connectionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("Соединение", icon: "antenna.radiowaves.left.and.right")

                field("Хост", icon: "network", text: $host, keyboard: .numbersAndPunctuation)
                field("Порт", icon: "number", text: $port, keyboard: .numberPad)
                field("Secret (hex)", icon: "key.fill", text: $secret, keyboard: .asciiCapable)
                field("Fake TLS домен", icon: "lock.fill", text: $fakeTLS, keyboard: .URL)
            }
        }
    }

    // MARK: - Toggles

    private var togglesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Режимы", icon: "switch.2")

                toggleRow("CF Proxy fallback", isOn: $fallbackCF)
                toggleRow("Proxy Protocol", isOn: $proxyProtocol)
                toggleRow("Force test DC", isOn: $forceTestDC)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            saveSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                Text(saved ? "Сохранено" : "Сохранить настройки")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(
                        saved
                            ? AnyShapeStyle(Color.green.opacity(0.7))
                            : AnyShapeStyle(LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing))
                    )
                    .shadow(color: Color.blue.opacity(0.4), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.proxyManager.isListening)
    }

    // MARK: - Helpers

    private func field(_ title: String, icon: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .frame(width: 22)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
                )
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
        }
        .tint(.cyan)
        .padding(.vertical, 6)
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
            Text(text)
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Load / Save

    private func loadFromSettings() {
        let s = appState.proxyManager.settings
        host = s.host
        port = "\(s.port)"
        secret = s.secret
        fakeTLS = s.fakeTLSDomain
        fallbackCF = s.fallbackCFProxy
        proxyProtocol = s.proxyProtocol
        forceTestDC = s.forceTestDC
    }

    private func saveSettings() {
        var s = appState.proxyManager.settings
        s.host = host.isEmpty ? "127.0.0.1" : host
        s.port = UInt16(port) ?? 1443
        s.secret = secret.isEmpty ? s.secret : secret
        s.fakeTLSDomain = fakeTLS.trimmingCharacters(in: .whitespaces)
        s.fallbackCFProxy = fallbackCF
        s.proxyProtocol = proxyProtocol
        s.forceTestDC = forceTestDC
        appState.proxyManager.settings = s
        s.save()

        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saved = false }
        }
        Log.info("Настройки сохранены")
    }
}