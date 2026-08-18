import Foundation
import Combine

/// The `ProxyManager` is the observable coordinator that owns the Swift proxy engine,
/// exposes state to SwiftUI, and forwards engine events into the shared log store.
@MainActor
final class ProxyManager: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case error(String)
    }

    // MARK: - Published state (UI-facing)
    @Published var status: Status = .stopped
    @Published var settings: ProxySettings
    @Published var activeConnections: Int = 0
    @Published var bytesUp: Int64 = 0
    @Published var bytesDown: Int64 = 0
    @Published var wsConnections: Int64 = 0
    @Published var isListening: Bool = false

    /// The actual engine running the proxy protocol. Non-nil only while running.
    private var engine: ProxyEngine?

    private var startedSettings: ProxySettings?

    init(settings: ProxySettings = .load()) {
        self.settings = settings
    }

    // MARK: - Bootstrap

    func bootstrap() {
        Log.info("TG WS Proxy инициализирован")
    }

    // MARK: - Lifecycle

    func start() {
        guard engine == nil else { return }
        // Persist current settings before starting.
        settings.save()

        status = .starting
        isListening = false
        activeConnections = 0
        bytesUp = 0
        bytesDown = 0
        wsConnections = 0

        let startSettings = settings
        startedSettings = startSettings

        Log.info("Запуск прокси на \(startSettings.host):\(startSettings.port)")

        let newEngine = ProxyEngine(settings: startSettings)
        newEngine.eventHandler = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        engine = newEngine

        newEngine.start { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.status = .running
                    self.isListening = true
                    self.logStartup(startSettings)
                    // Keep the app alive in the background while the proxy runs.
                    BackgroundKeepAlive.shared.start()
                case .failure(let error):
                    self.status = .error(error.localizedDescription)
                    Log.error("Ошибка запуска: \(error.localizedDescription)")
                    self.engine = nil
                }
            }
        }
    }

    func stop() {
        guard let engine else { return }
        status = .stopping
        Log.info("Остановка прокси")
        engine.stop { [weak self] in
            Task { @MainActor in
                self?.engine = nil
                self?.status = .stopped
                self?.isListening = false
                self?.activeConnections = 0
                BackgroundKeepAlive.shared.stop()
                Log.info("Прокси остановлен")
            }
        }
    }

    func toggle() {
        switch status {
        case .running, .starting, .stopping:
            stop()
        default:
            start()
        }
    }

    // MARK: - Event handling

    private func handle(_ event: ProxyEngine.Event) {
        switch event {
        case .clientConnected(let count):
            activeConnections = count
        case .traffic(let up, let down, let wsCount):
            bytesUp = up
            bytesDown = down
            wsConnections = wsCount
        }
    }

    private func logStartup(_ s: ProxySettings) {
        Log.info("Прокси слушает на \(s.host):\(s.port)")
        Log.info("Secret: \(s.secret)")
        if !s.fakeTLSDomain.isEmpty {
            Log.info("Fake TLS: \(s.fakeTLSDomain)")
        }
        Log.info("Подключение (dd): \(s.ddLink)")
        if let link = s.eeLink {
            Log.info("Подключение (ee): \(link)")
        }
    }

    /// The shareable link based on the active configuration.
    var connectionLink: String {
        if let link = settings.eeLink {
            return link
        }
        return settings.ddLink
    }
}