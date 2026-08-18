import Foundation
import Network

/// The core proxy engine. Owns a TCP listener and dispatches each accepted
/// connection to a `ClientConnection` that runs the MTProto-over-WebSocket
/// bridge. Mirrors the orchestration in `proxy/tg_ws_proxy.py`.
final class ProxyEngine {
    enum Event {
        case clientConnected(Int)
        case traffic(up: Int64, down: Int64, wsCount: Int64)
    }

    private let settings: ProxySettings
    private var listener: NWListener?
    private var activeConnections: [ClientConnection] = []
    private let queue = DispatchQueue(label: "tgws.proxyEngine", qos: .userInitiated)

    private var totalUp: Int64 = 0
    private var totalDown: Int64 = 0
    private var totalWS: Int64 = 0

    var eventHandler: ((Event) -> Void)?

    init(settings: ProxySettings) {
        self.settings = settings
    }

    // MARK: - Start / Stop

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: settings.port) else {
            completion(.failure(NSError(domain: "tgws", code: 1, userInfo: [NSLocalizedDescriptionKey: "Некорректный порт"])))
            return
        }
        guard let secret = settings.secretBytes, secret.count > 0 else {
            completion(.failure(NSError(domain: "tgws", code: 2, userInfo: [NSLocalizedDescriptionKey: "Некорректный secret"])))
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: port)
            self.listener = newListener

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection, secret: secret)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    completion(.success(()))
                case .failed(let error):
                    completion(.failure(error))
                default:
                    break
                }
            }
            newListener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop(completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { completion(); return }
            self.listener?.cancel()
            self.listener = nil
            let conns = self.activeConnections
            self.activeConnections.removeAll()
            for c in conns {
                c.forceClose()
            }
            completion()
        }
    }

    // MARK: - Connection management

    private func handleNewConnection(_ connection: NWConnection, secret: Data) {
        let client = ClientConnection(
            connection: connection,
            settings: settings,
            secret: secret,
            onTraffic: { [weak self] up, down in
                self?.accumulateTraffic(up: up, down: down)
            },
            onClose: { [weak self] client in
                self?.removeConnection(client)
            }
        )
        activeConnections.append(client)
        client.start()
        reportConnections()
    }

    private func removeConnection(_ client: ClientConnection) {
        activeConnections.removeAll { $0 === client }
        reportConnections()
    }

    private func reportConnections() {
        eventHandler?(.clientConnected(activeConnections.count))
    }

    private func accumulateTraffic(up: Int64, down: Int64) {
        totalUp += up
        totalDown += down
        eventHandler?(.traffic(up: totalUp, down: totalDown, wsCount: Int64(totalWS)))
    }
}