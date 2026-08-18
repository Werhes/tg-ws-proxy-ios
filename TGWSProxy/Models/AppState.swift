import Foundation
import Combine

/// Application-wide shared state that bridges the proxy engine and the SwiftUI UI.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Published state
    @Published var proxyManager: ProxyManager

    @Published var selectedTab: Tab = .proxy

    @Published var activeConnections: Int = 0
    @Published var bytesUp: Int64 = 0
    @Published var bytesDown: Int64 = 0
    @Published var wsConnections: Int64 = 0

    private var cancellables = Set<AnyCancellable>()

    private init() {
        proxyManager = ProxyManager()
        proxyManager.$activeConnections
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.activeConnections = value
            }
            .store(in: &cancellables)

        proxyManager.$bytesUp
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.bytesUp = value
            }
            .store(in: &cancellables)

        proxyManager.$bytesDown
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.bytesDown = value
            }
            .store(in: &cancellables)

        proxyManager.$wsConnections
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.wsConnections = value
            }
            .store(in: &cancellables)
    }
}

/// The three primary tabs of the application.
enum Tab: String, CaseIterable, Identifiable {
    case proxy
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .proxy: return "Прокси"
        case .settings: return "Настройки"
        case .logs: return "Логи"
        }
    }

    var systemImage: String {
        switch self {
        case .proxy: return "network"
        case .settings: return "gearshape.fill"
        case .logs: return "doc.plaintext"
        }
    }
}