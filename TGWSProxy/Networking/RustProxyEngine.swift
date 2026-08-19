import Foundation
import Combine

/// Swift wrapper around the Rust core (`libtgwsproxy.a`).
///
/// Exposes a `ProxyEngine`-compatible interface so `ProxyManager` can start/stop
/// the proxy and receive traffic/connection events, while all MTProto-over-WebSocket
/// logic runs inside the Rust engine.
final class RustProxyEngine {
    enum Event {
        case clientConnected(Int)
        case traffic(up: Int64, down: Int64, wsCount: Int64)
    }

    private let settings: ProxySettings
    private var statsTimer: Timer?
    private var running = false

    var eventHandler: ((Event) -> Void)?

    init(settings: ProxySettings) {
        self.settings = settings
    }

    deinit {
        statsTimer?.invalidate()
    }

    // MARK: - Start / Stop

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard !running else {
            completion(.failure(tgwsError("Прокси уже запущен")))
            return
        }

        // Configure the Rust engine before starting.
        SetSecret(settings.secret)
        SetPoolSize(4)
        SetCfProxyConfig(settings.fallbackCFProxy ? 1 : 0, 0, "")

        let dcIPs = Self.dcIPsString(settings: settings)
        let host = settings.host
        let port = Int32(settings.port)

        let result = StartProxy(host, port, dcIPs, settings.secret, 0)
        switch result {
        case 0:
            running = true
            completion(.success(()))
            startStatsTimer()
        case -1:
            completion(.failure(tgwsError("Прокси уже запущен")))
        case -3:
            completion(.failure(tgwsError("Не удалось занять порт \(settings.port)")))
        default:
            completion(.failure(tgwsError("Ошибка запуска Rust-ядра (\(result))")))
        }
    }

    func stop(completion: @escaping () -> Void) {
        statsTimer?.invalidate()
        statsTimer = nil
        _ = StopProxy()
        running = false
        completion()
    }

    // MARK: - Stats polling

    private func startStatsTimer() {
        statsTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollStats()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    private func pollStats() {
        guard running else { return }
        guard let raw = takeCString(GetRawStats()) else { return }
        // Format: "active,bytesUp,bytesDown,wsConnections"
        let parts = raw.split(separator: ",").map { String($0) }
        guard parts.count >= 4,
              let active = Int(parts[0]),
              let up = Int64(parts[1]),
              let down = Int64(parts[2]),
              let ws = Int64(parts[3])
        else { return }

        eventHandler?(.clientConnected(active))
        eventHandler?(.traffic(up: up, down: down, wsCount: ws))
    }

    // MARK: - Helpers

    private func tgwsError(_ message: String) -> Error {
        NSError(domain: "tgws", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Reads and frees a C string returned by the Rust FFI.
    private func takeCString(_ ptr: UnsafeMutablePointer<CChar>?) -> String? {
        guard let ptr = ptr else { return nil }
        defer { FreeString(ptr) }
        return String(cString: ptr)
    }

    /// Builds the `dc:ip,dc:ip` string consumed by `StartProxy`.
    /// Uses the user's DC redirects; falls back to the default Telegram DC IPs.
    static func dcIPsString(settings: ProxySettings) -> String {
        var map = settings.dcRedirects

        // Ensure all default DCs are present so the pool can reach any DC.
        for (dc, ip) in MTProtoConstants.dcDefaultIPs {
            if map[String(dc)] == nil {
                map[String(dc)] = ip
            }
        }

        let pairs = map
            .sorted { Int($0.key) ?? 0 < Int($1.key) ?? 0 }
            .compactMap { key, value -> String? in
                guard !value.isEmpty else { return nil }
                return "\(key):\(value)"
            }
        return pairs.joined(separator: ",")
    }
}