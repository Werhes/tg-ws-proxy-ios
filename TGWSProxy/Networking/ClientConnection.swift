import Foundation
import Network

/// Handles a single proxied client connection:
///  1. Reads the client's MTProto init (with optional fake-TLS masking).
///  2. Verifies the secret and determines the target DC.
///  3. Opens a WebSocket to Telegram and bridges traffic with re-encryption.
final class ClientConnection {
    private let connection: NWConnection
    private let settings: ProxySettings
    private let secret: Data
    private let queue = DispatchQueue(label: "tgws.clientConnection", qos: .userInitiated)

    private var onTraffic: (Int64, Int64) -> Void
    private var onClose: (ClientConnection) -> Void

    private var receiveBuffer = Data()
    private var isClosed = false
    private var clientWS: WebSocketClient?
    private var remoteConnection: NWConnection?

    private var upBytes: Int64 = 0
    private var downBytes: Int64 = 0

    /// Sink for encrypted client data once the bridge is established.
    private var upstreamSink: ((Data) -> Void)?

    // Session crypto state
    private var ctx: CryptoCtx?
    private var relayInit: Data?
    private var splitter: MsgSplitter?

    init(
        connection: NWConnection,
        settings: ProxySettings,
        secret: Data,
        onTraffic: @escaping (Int64, Int64) -> Void,
        onClose: @escaping (ClientConnection) -> Void
    ) {
        self.connection = connection
        self.settings = settings
        self.secret = secret
        self.onTraffic = onTraffic
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.beginHandshake()
            case .failed(let error):
                Log.debug("Client connection failed: \(error.localizedDescription)")
                self?.forceClose()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Handshake

    private func beginHandshake() {
        Log.debug("Новое клиентское соединение")
        // Read first byte to detect TLS masking.
        readExact(1) { [weak self] firstByte in
            guard let self else { return }
            if firstByte.first == FakeTLS.recordHandshake && !self.settings.fakeTLSDomain.isEmpty {
                self.handleFakeTLS(firstByte: firstByte)
            } else if firstByte.first == FakeTLS.recordHandshake && self.settings.fakeTLSDomain.isEmpty {
                // Client sent TLS but fake TLS not enabled → treat as plain HTTP redirect.
                self.sendHTTPRedirect()
            } else {
                self.handlePlainHandshake(firstByte: firstByte)
            }
        }
    }

    private func handlePlainHandshake(firstByte: Data) {
        readExact(MTProtoConstants.handshakeLen - 1) { [weak self] rest in
            guard let self else { return }
            var full = firstByte
            full.append(rest)
            self.processHandshake(full)
        }
    }

    private func handleFakeTLS(firstByte: Data) {
        readExact(4) { [weak self] headerRest in
            guard let self else { return }
            let tlsHeader = firstByte + headerRest
            let recordLen = Int(tlsHeader[tlsHeader.startIndex + 3]) << 8 | Int(tlsHeader[tlsHeader.startIndex + 4])
            self.readExact(recordLen) { recordBody in
                var clientHello = tlsHeader
                clientHello.append(recordBody)
                self.verifyAndProcessClientHello(clientHello)
            }
        }
    }

    private func verifyAndProcessClientHello(_ clientHello: Data) {
        if let tls = FakeTLS.verifyClientHello(clientHello, secret: secret) {
            let serverHello = FakeTLS.buildServerHello(secret: secret, clientRandom: tls.clientRandom, sessionID: tls.sessionID)
            send(data: serverHello) { [weak self] in
                guard let self else { return }
                // Read the 64-byte obfuscated init inside the TLS stream.
                self.readExact(MTProtoConstants.handshakeLen) { initData in
                    self.processHandshake(initData)
                }
            }
        } else {
            // Failed fake-TLS verification → masking redirect.
            Log.debug("Fake TLS verify failed → masking")
            self.sendHTTPRedirect()
        }
    }

    private func sendHTTPRedirect() {
        let redirect = """
        HTTP/1.1 301 Moved Permanently\r
        Location: https://\(settings.fakeTLSDomain.isEmpty ? "telegram.org" : settings.fakeTLSDomain)/\r
        Content-Length: 0\r
        Connection: close\r
        \r
        """
        send(data: Data(redirect.utf8)) { [weak self] in
            self?.forceClose()
        }
    }

    private func processHandshake(_ handshake: Data) {
        guard let result = Handshake.tryHandshake(handshake, secret: secret) else {
            Log.warning("Неверный handshake (secret или протокол)")
            // Drain remaining data.
            forceClose()
            return
        }

        var dc = result.dc
        let isMedia = result.isMedia
        let isTestDC = settings.forceTestDC || dc >= 10000
        if dc >= 10000 { dc -= 10000 }

        let protoInt: UInt32
        switch result.protoTag {
        case MTProtoConstants.protoTagAbridged:
            protoInt = MTProtoConstants.protoAbridgedInt
        case MTProtoConstants.protoTagIntermediate:
            protoInt = MTProtoConstants.protoIntermediateInt
        default:
            protoInt = MTProtoConstants.protoPaddedIntermediateInt
        }

        let dcIdx: Int16 = isMedia ? -Int16(dc) : Int16(dc)
        let relayInit = Handshake.generateRelayInit(protoTag: result.protoTag, dcIdx: dcIdx)
        self.relayInit = relayInit

        guard let ctx = try? CryptoContextBuilder.build(
            clientDecPrekeyIV: result.clientDecPrekeyIV,
            secret: secret,
            relayInit: relayInit
        ) else {
            Log.error("Не удалось построить крипто-контекст")
            forceClose()
            return
        }
        self.ctx = ctx
        self.splitter = try? MsgSplitter(relayInit: relayInit, protoInt: protoInt)

        Log.info("Handshake OK: DC\(dc)\(isMedia ? " media" : "") proto=0x\(String(protoInt, radix: 16))")

        connectToTelegram(dc: dc, isMedia: isMedia, isTestDC: isTestDC, relayInit: relayInit)
    }

    // MARK: - Connect to Telegram

    private func connectToTelegram(dc: Int, isMedia: Bool, isTestDC: Bool, relayInit: Data) {
        let wsPath = isTestDC ? MTProtoConstants.wsPathTest : MTProtoConstants.wsPath
        let domains = MTProtoConstants.wsDomains(dc: dc, isMedia: isMedia)
        let target = settings.dcRedirects["\(dc)"] ?? MTProtoConstants.dcDefaultIPs[dc] ?? "149.154.167.51"

        // Try domains in order.
        tryDomains(domains, dc: dc, isMedia: isMedia, isTestDC: isTestDC, target: target, wsPath: wsPath, index: 0, relayInit: relayInit)
    }

    private func tryDomains(
        _ domains: [String],
        dc: Int,
        isMedia: Bool,
        isTestDC: Bool,
        target: String,
        wsPath: String,
        index: Int,
        relayInit: Data
    ) {
        guard index < domains.count else {
            Log.warning("DC\(dc) WebSocket не доступен → fallback")
            doFallback(dc: dc, isMedia: isMedia, isTestDC: isTestDC, relayInit: relayInit)
            return
        }
        let domain = domains[index]
        let url = "wss://\(domain)\(wsPath)"
        Log.info("DC\(dc) -> \(url) via \(target)")

        let ws = WebSocketClient()
        self.clientWS = ws
        ws.connect(host: target, domain: domain, path: wsPath) { [weak self] result in
            switch result {
            case .success:
                Log.info("DC\(dc) WebSocket готов")
                self?.beginBridge(ws: ws, relayInit: relayInit)
            case .failure(let error):
                Log.warning("DC\(dc) WS failed (\(domain)): \(error.localizedDescription)")
                self?.tryDomains(domains, dc: dc, isMedia: isMedia, isTestDC: isTestDC, target: target, wsPath: wsPath, index: index + 1, relayInit: relayInit)
            }
        }
    }

    private func beginBridge(ws: WebSocketClient, relayInit: Data) {
        guard let ctx else { return }
        // Send relay init to Telegram first.
        ws.send(relayInit)

        // Route encrypted client data into the WebSocket.
        upstreamSink = { data in
            ws.send(data)
        }

        // Start reading from client (tcp → ws).
        startClientReadLoop()

        // Configure ws → client direction.
        ws.onMessage = { [weak self] data in
            self?.handleWSMessage(data)
        }
        ws.onClose = { [weak self] in
            self?.forceClose()
        }
    }

    // MARK: - Client → WS (upstream)

    private func startClientReadLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.upBytes += Int64(data.count)
                self.onTraffic(self.upBytes, self.downBytes)
                self.processClientChunk(data)
            }
            if isComplete || error != nil {
                self.forceClose()
            } else {
                self.startClientReadLoop()
            }
        }
    }

    private func processClientChunk(_ chunk: Data) {
        guard let ctx, let sink = upstreamSink else { return }
        do {
            let plain = try ctx.cltDec.update(chunk)
            let encrypted = try ctx.tgEnc.update(plain)
            if let splitter {
                let parts = try splitter.split(chunk: encrypted)
                if parts.count > 1 {
                    for part in parts { sink(part) }
                } else if let first = parts.first {
                    sink(first)
                }
            } else {
                sink(encrypted)
            }
        } catch {
            Log.error("Ошибка шифрования tcp→ws: \(error.localizedDescription)")
            forceClose()
        }
    }

    // MARK: - WS → Client (downstream)

    private func handleWSMessage(_ data: Data) {
        guard let ctx else { return }
        downBytes += Int64(data.count)
        onTraffic(upBytes, downBytes)
        do {
            let plain = try ctx.tgDec.update(data)
            let encrypted = try ctx.cltEnc.update(plain)
            send(data: encrypted, completion: nil)
        } catch {
            Log.error("Ошибка шифрования ws→tcp: \(error.localizedDescription)")
            forceClose()
        }
    }

    // MARK: - Fallback

    private func doFallback(dc: Int, isMedia: Bool, isTestDC: Bool, relayInit: Data) {
        // TCP fallback to the DC's default IP on port 443.
        let ipTable = isTestDC ? MTProtoConstants.dcTestIPs : MTProtoConstants.dcDefaultIPs
        guard let dst = ipTable[dc] else {
            Log.warning("Нет fallback для DC\(dc)")
            forceClose()
            return
        }
        Log.info("DC\(dc) -> TCP fallback to \(dst):443")

        let remote = NWConnection(
            to: NWEndpoint.hostPort(host: .ipv4(IPv4Address(dst) ?? IPv4Address("149.154.167.51")!), port: 443),
            using: .tcp
        )
        self.remoteConnection = remote
        remote.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.send(data: relayInit) { }
                self.beginTCPBridge(remote: remote)
            case .failed(let error):
                Log.warning("TCP fallback failed: \(error.localizedDescription)")
                self.forceClose()
            default:
                break
            }
        }
        remote.start(queue: queue)
    }

    private func beginTCPBridge(remote: NWConnection) {
        guard let ctx else { return }

        // Route encrypted client data into the remote TCP connection.
        upstreamSink = { data in
            remote.send(content: data, completion: .contentProcessed { _ in })
        }

        // Start reading from client (tcp → remote).
        startClientReadLoop()

        // Start reading from remote (remote → tcp).
        readRemoteLoop(remote)
    }

    private func readRemoteLoop(_ remote: NWConnection) {
        guard let ctx else { return }
        remote.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.downBytes += Int64(data.count)
                self.onTraffic(self.upBytes, self.downBytes)
                if let plain = try? ctx.tgDec.update(data),
                   let encrypted = try? ctx.cltEnc.update(plain) {
                    self.send(data: encrypted, completion: nil)
                }
            }
            if isComplete || error != nil {
                self.forceClose()
            } else {
                self.readRemoteLoop(remote)
            }
        }
    }

    // MARK: - Low-level helpers

    private func readExact(_ count: Int, completion: @escaping (Data) -> Void) {
        if receiveBuffer.count >= count {
            let data = Data(receiveBuffer.prefix(count))
            receiveBuffer.removeFirst(count)
            completion(data)
            return
        }
        let needed = count - receiveBuffer.count
        connection.receive(minimumIncompleteLength: needed, maximumLength: max(needed, 65536)) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.receiveBuffer.append(data)
            }
            if self.receiveBuffer.count >= count {
                let result = Data(self.receiveBuffer.prefix(count))
                self.receiveBuffer.removeFirst(count)
                completion(result)
            } else if isComplete || error != nil {
                self.forceClose()
            } else {
                self.readExact(count - self.receiveBuffer.count, completion: completion)
            }
        }
    }

    private func send(data: Data, completion: (() -> Void)?) {
        connection.send(content: data, completion: .contentProcessed { _ in
            completion?()
        })
    }

    func forceClose() {
        guard !isClosed else { return }
        isClosed = true
        clientWS?.close()
        remoteConnection?.cancel()
        connection.cancel()
        onClose(self)
    }
}