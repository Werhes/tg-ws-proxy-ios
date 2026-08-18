import Foundation
import Network
import Security
import CryptoKit

/// A raw WebSocket client that lets us connect to a specific IP while
/// presenting a chosen SNI/domain — mirroring `raw_websocket.py`.
final class WebSocketClient {
    enum WebSocketError: Error {
        case handshake(Int, String)
        case timeout
        case connection(Error)
        case closed
        case fragmentedTooLarge
    }

    private static let maxMessageLen = 16 * 1024 * 1024

    private let queue = DispatchQueue(label: "tgws.webSocket", qos: .userInitiated)
    private var connection: NWConnection?
    private var handshakePending = true
    private var pendingData = Data()
    private var isClosed = false

    private let opCont: UInt8 = 0x0
    private let opBinary: UInt8 = 0x2
    private let opClose: UInt8 = 0x8
    private let opPing: UInt8 = 0x9
    private let opPong: UInt8 = 0xA

    private var receivedFrames = Data()
    private var closeHandlers: (() -> Void)?
    var onClose: (() -> Void)? {
        get { closeHandlers }
        set {
            queue.sync {
                if isClosed {
                    newValue?()
                } else {
                    closeHandlers = newValue
                }
            }
        }
    }

    // MARK: - Connect

    /// Opens a raw TCP + TLS connection to `host` (IP) using `sni` for the
    /// server-name indication, performs the HTTP upgrade, then calls `onOpen`.
    func connect(
        host: String,
        domain: String,
        port: UInt16 = 443,
        path: String = "/apiws",
        sni: String? = nil,
        timeout: TimeInterval = 10.0,
        onOpen: @escaping (Result<Void, WebSocketError>) -> Void
    ) {
        let effectiveSNI = sni ?? domain
        let hostEndpoint = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address(host) ?? IPv4Address("127.0.0.1")!),
            port: NWEndpoint.Port(rawValue: port)!
        )

        let parameters = NWParameters.tls
        // Configure the existing TLS options for SNI and minimum TLS version.
        let tlsOptions = parameters.defaultProtocolStack.applicationProtocols
            .compactMap { $0 as? NWProtocolTLS.Options }
            .first ?? NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)
        effectiveSNI.withCString { cSNI in
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, cSNI)
        }
        if parameters.defaultProtocolStack.applicationProtocols.isEmpty {
            parameters.defaultProtocolStack.applicationProtocols = [tlsOptions]
        }

        let conn = NWConnection(to: hostEndpoint, using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.async {
                    self?.performHandshake(domain: domain, path: path, timeout: timeout, onOpen: onOpen)
                }
            case .failed(let error):
                onOpen(.failure(.connection(error)))
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func performHandshake(
        domain: String,
        path: String,
        timeout: TimeInterval,
        onOpen: @escaping (Result<Void, WebSocketError>) -> Void
    ) {
        guard let conn = connection else {
            onOpen(.failure(.closed)); return
        }
        let wsKey = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = """
        GET \(path) HTTP/1.1\r
        Host: \(domain)\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(wsKey)\r
        Sec-WebSocket-Version: 13\r
        Sec-WebSocket-Protocol: binary\r
        \r
        """
        conn.send(content: request.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { onOpen(.failure(.closed)); return }
            if let error {
                onOpen(.failure(.connection(error)))
                return
            }
            self.readHandshakeResponse(timeout: timeout, onOpen: onOpen)
        })
    }

    private func readHandshakeResponse(
        timeout: TimeInterval,
        onOpen: @escaping (Result<Void, WebSocketError>) -> Void
    ) {
        guard let conn = connection else {
            onOpen(.failure(.closed)); return
        }
        let deadline = Date().addingTimeInterval(timeout)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.pendingData.append(data)
            }
            if let headerEnd = self.pendingData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = self.pendingData[..<headerEnd.lowerBound]
                self.pendingData.removeSubrange(..<headerEnd.upperBound)
                self.handshakePending = false
                self.handleHandshakeHeader(headerData, isComplete: isComplete, onOpen: onOpen)
                return
            }
            if isComplete {
                onOpen(.failure(.closed))
                return
            }
            if error != nil {
                onOpen(.failure(.closed))
                return
            }
            if Date() > deadline {
                onOpen(.failure(.timeout))
                return
            }
            // keep reading
            self.readHandshakeResponse(timeout: deadline.timeIntervalSinceNow, onOpen: onOpen)
        }
    }

    private func handleHandshakeHeader(
        _ headerData: Data,
        isComplete: Bool,
        onOpen: @escaping (Result<Void, WebSocketError>) -> Void
    ) {
        guard let text = String(data: headerData, encoding: .utf8) else {
            onOpen(.failure(.closed)); return
        }
        let lines = text.split(separator: "\r\n").map(String.init)
        guard let first = lines.first else {
            onOpen(.failure(.closed)); return
        }
        let parts = first.split(separator: " ").map(String.init)
        let statusCode = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
        if statusCode == 101 {
            onOpen(.success(()))
            // Parse any bytes already buffered after the header, then begin the loop.
            if !pendingData.isEmpty {
                parseFrames()
                pendingData.removeAll()
            }
            startReceiveLoop()
            return
        }
        onOpen(.failure(.handshake(statusCode, first)))
    }

    // MARK: - Send

    func send(_ data: Data) {
        queue.async {
            guard let conn = self.connection, !self.handshakePending, !self.isClosed else { return }
            var frame = Data()
            frame.append(0x80 | self.opBinary) // FIN + binary
            let len = data.count
            if len < 126 {
                frame.append(UInt8(len))
            } else if len <= 0xFFFF {
                frame.append(126)
                frame.append(UInt8((len >> 8) & 0xFF))
                frame.append(UInt8(len & 0xFF))
            } else {
                frame.append(127)
                for i in stride(from: 7, through: 0, by: -1) {
                    frame.append(UInt8((UInt64(len) >> (UInt64(i) * 8)) & 0xFF))
                }
            }
            frame.append(data)
            conn.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    func sendBatch(_ datas: [Data]) {
        for d in datas { send(d) }
    }

    // MARK: - Receive

    /// Starts the continuous receive loop after the handshake completes.
    private func startReceiveLoop() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.pendingData.append(data)
                self.parseFrames()
            }
            if isComplete || error != nil {
                self.close()
            } else {
                self.startReceiveLoop()
            }
        }
    }

    private func parseFrames() {
        var offset = 0
        while true {
            guard pendingData.count - offset >= 2 else { break }
            let first = pendingData[pendingData.startIndex + offset]
            let second = pendingData[pendingData.startIndex + offset + 1]
            let fin = (first & 0x80) != 0
            let opcode = first & 0x0F
            var payloadLen = Int(second & 0x7F)
            var headerLen = 2
            if payloadLen == 126 {
                guard pendingData.count - offset >= 4 else { break }
                payloadLen = Int(pendingData[pendingData.startIndex + offset + 2]) << 8
                    | Int(pendingData[pendingData.startIndex + offset + 3])
                headerLen = 4
            } else if payloadLen == 127 {
                guard pendingData.count - offset >= 10 else { break }
                var length: UInt64 = 0
                for i in 0..<8 {
                    length = (length << 8) | UInt64(pendingData[pendingData.startIndex + offset + 2 + i])
                }
                payloadLen = Int(length)
                headerLen = 10
            }
            var maskOffset = headerLen
            let masked = (second & 0x80) != 0
            if masked {
                maskOffset += 4
                guard pendingData.count - offset >= maskOffset else { break }
            }
            guard pendingData.count - offset >= maskOffset + payloadLen else { break }

            var payload: Data
            let payloadStart = offset + maskOffset
            if masked {
                let mask = Array(pendingData[offset + headerLen..<offset + maskOffset])
                payload = Data(pendingData[payloadStart..<payloadStart + payloadLen].enumerated().map { index, byte in
                    byte ^ mask[index % 4]
                })
            } else {
                payload = Data(pendingData[payloadStart..<payloadStart + payloadLen])
            }
            offset = payloadStart + payloadLen

            switch opcode {
            case opBinary, opCont:
                if receivedFrames.count + payload.count > Self.maxMessageLen {
                    close(); return
                }
                receivedFrames.append(payload)
                if fin {
                    let message = receivedFrames
                    receivedFrames.removeAll()
                    messageHandler?(message)
                }
            case opPing:
                sendPong(payload)
            case opPong:
                break
            case opClose:
                close(); return
            default:
                break
            }
        }
        if offset > 0 {
            pendingData.removeFirst(offset)
        }
    }

    private var messageHandler: ((Data) -> Void)?
    var onMessage: ((Data) -> Void)? {
        get { messageHandler }
        set { messageHandler = newValue }
    }

    private func sendPong(_ payload: Data) {
        guard let conn = connection else { return }
        var frame = Data()
        frame.append(0x80 | opPong)
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        }
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    func close() {
        queue.async {
            guard !self.isClosed else { return }
            self.isClosed = true
            let handler = self.closeHandlers
            self.connection?.cancel()
            self.connection = nil
            DispatchQueue.main.async { handler?() }
        }
    }

    deinit {
        connection?.cancel()
    }
}