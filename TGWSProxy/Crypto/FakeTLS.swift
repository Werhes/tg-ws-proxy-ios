import Foundation
import CryptoKit
import CommonCrypto

/// Fake TLS masquerading (port of `proxy/fake_tls.py`).
/// This allows the proxy to present itself as a real HTTPS server while
/// actually performing the MTProto handshake inside a TLS-like wrapper.
enum FakeTLS {
    static let recordHandshake: UInt8 = 0x16
    static let recordCCS: UInt8 = 0x14
    static let recordAppdata: UInt8 = 0x17

    static let clientRandomOffset = 11
    static let clientRandomLen = 32
    static let sessionIDOffset = 44
    static let sessionIDLen = 32

    static let timestampTolerance: Int64 = 120
    static let tlsAppdataMax = 16384

    static let ccsFrame: [UInt8] = [0x14, 0x03, 0x03, 0x00, 0x01, 0x01]

    /// The fixed ServerHello template (TLS 1.3 + ECDHE x25519).
    static let serverHelloTemplate: [UInt8] = [
        0x16, 0x03, 0x03, 0x00, 0x7a,
        0x02, 0x00, 0x00, 0x76,
        0x03, 0x03,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0x20,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0x13, 0x01, 0x00,
        0x00, 0x2e,
        0x00, 0x33, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0x00, 0x2b, 0x00, 0x02, 0x03, 0x04,
    ]

    static let shRandomOff = 11
    static let shSessidOff = 44
    static let shPubkeyOff = 89

    /// Verifies a ClientHello against the proxy secret.
    /// Returns (clientRandom, sessionID, timestamp) on success, or nil.
    static func verifyClientHello(_ data: Data, secret: Data) -> (clientRandom: Data, sessionID: Data, timestamp: UInt32)? {
        let n = data.count
        guard n >= 43 else { return nil }
        guard data[data.startIndex] == recordHandshake else { return nil }
        guard data[data.startIndex + 5] == 0x01 else { return nil }

        let clientRandom = Data(data[
            data.startIndex + clientRandomOffset
            ..< data.startIndex + clientRandomOffset + clientRandomLen
        ])

        var zeroed = data
        zeroed.replaceSubrange(
            zeroed.startIndex + clientRandomOffset
            ..< zeroed.startIndex + clientRandomOffset + clientRandomLen,
            with: Data(repeating: 0, count: clientRandomLen)
        )

        let expected256 = Data(HMAC<SHA256>(key: secret).authenticate(zeroed))

        // Compare first 28 bytes with the first 28 bytes of client random.
        let cr = Array(clientRandom.prefix(28))
        let ex = Array(expected256.prefix(28))
        guard cr == ex else { return nil }

        // Timestamp is XOR of bytes 28..32 of client random with expected.
        var ts: UInt32 = 0
        for i in 0..<4 {
            let b = clientRandom[clientRandom.startIndex + 28 + i] ^ expected256[expected256.startIndex + 28 + i]
            ts |= UInt32(b) << (8 * UInt32(i))
        }

        let now = UInt32(Date().timeIntervalSince1970)
        let diff = Int64(now) - Int64(ts)
        if abs(diff) > timestampTolerance {
            return nil
        }

        var sessionID = Data(repeating: 0, count: sessionIDLen)
        if n >= sessionIDOffset + sessionIDLen && data[data.startIndex + 43] == 0x20 {
            sessionID = Data(data[
                data.startIndex + sessionIDOffset
                ..< data.startIndex + sessionIDOffset + sessionIDLen
            ])
        }

        return (clientRandom, sessionID, ts)
    }

    /// Builds a ServerHello + CCS + app-data response.
    static func buildServerHello(secret: Data, clientRandom: Data, sessionID: Data) -> Data {
        var sh = serverHelloTemplate
        sh.replaceSubrange(
            shSessidOff..<(shSessidOff + 32),
            with: Array(sessionID.prefix(32))
        )
        var pubkey = [UInt8](repeating: 0, count: 32)
        SecRandomCopyBytes(kSecRandomDefault, pubkey.count, &pubkey)
        sh.replaceSubrange(
            shPubkeyOff..<(shPubkeyOff + 32),
            with: pubkey
        )

        let encryptedSize = Int.random(in: 1900...2100)
        var encryptedData = [UInt8](repeating: 0, count: encryptedSize)
        SecRandomCopyBytes(kSecRandomDefault, encryptedData.count, &encryptedData)
        let appRecord = [recordAppdata, 0x03, 0x03] + UInt16(encryptedSize).bigEndianBytes + encryptedData

        var response = sh + ccsFrame + appRecord

        // server_random = HMAC(secret, client_random + response)
        let hmacInput = clientRandom + Data(response)
        let serverRandom = Data(HMAC<SHA256>(key: secret).authenticate(hmacInput))
        response.replaceSubrange(
            shRandomOff..<(shRandomOff + 32),
            with: Array(serverRandom.prefix(32))
        )
        return Data(response)
    }
}

private extension UInt16 {
    var bigEndianBytes: [UInt8] {
        [UInt8(self >> 8), UInt8(self & 0xFF)]
    }
}