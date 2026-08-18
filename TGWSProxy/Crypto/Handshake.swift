import Foundation
import CryptoKit

/// Result of parsing a client handshake (mirrors Python `_try_handshake`).
struct HandshakeResult {
    let dc: Int
    let isMedia: Bool
    let protoTag: [UInt8]
    let clientDecPrekeyIV: Data
}

/// Implements the obfuscation2 handshake generation and verification.
enum Handshake {
    /// Decrypts and verifies a client handshake against the proxy secret.
    /// Returns nil if the secret or proto tag is wrong.
    static func tryHandshake(_ handshake: Data, secret: Data) -> HandshakeResult? {
        let decPrekeyAndIV = handshake[
            handshake.startIndex.advanced(by: MTProtoConstants.skipLen)
            ..< handshake.startIndex.advanced(by: MTProtoConstants.skipLen + MTProtoConstants.prekeyLen + MTProtoConstants.ivLen)
        ]
        let decPrekey = decPrekeyAndIV.prefix(MTProtoConstants.prekeyLen)
        let decIV = decPrekeyAndIV.dropFirst(MTProtoConstants.prekeyLen)

        let decKey = Data(SHA256.hash(data: decPrekey + secret))

        guard let decryptor = try? AESCipher(key: decKey, iv: decIV) else {
            return nil
        }
        guard let decrypted = try? decryptor.update(handshake) else {
            return nil
        }

        let protoTag = Array(decrypted[
            decrypted.startIndex.advanced(by: MTProtoConstants.protoTagPos)
            ..< decrypted.startIndex.advanced(by: MTProtoConstants.protoTagPos + 4)
        ])

        guard protoTag == MTProtoConstants.protoTagAbridged
            || protoTag == MTProtoConstants.protoTagIntermediate
            || protoTag == MTProtoConstants.protoTagSecure
        else {
            return nil
        }

        let dcIdx = decrypted.littleEndianInt16(at: MTProtoConstants.dcIdxPos)
        let dc = dcIdx.pythonAbs
        let isMedia = dcIdx < 0

        return HandshakeResult(
            dc: dc,
            isMedia: isMedia,
            protoTag: protoTag,
            clientDecPrekeyIV: decPrekeyAndIV
        )
    }

    /// Generates a fresh relay init (the 64-byte obfuscated header sent to Telegram).
    static func generateRelayInit(protoTag: [UInt8], dcIdx: Int16) -> Data {
        while true {
            var rnd = [UInt8](repeating: 0, count: MTProtoConstants.handshakeLen)
            let status = SecRandomCopyBytes(kSecRandomDefault, rnd.count, &rnd)
            if status != errSecSuccess {
                rnd = randomFallback(count: rnd.count)
            }

            if MTProtoConstants.reservedFirstBytes.contains(rnd[0]) { continue }
            if MTProtoConstants.reservedStarts.contains(Array(rnd.prefix(4))) { continue }
            if Array(rnd[4..<8]) == MTProtoConstants.reservedContinue { continue }

            let encKey = Data(rnd[
                MTProtoConstants.skipLen
                ..< MTProtoConstants.skipLen + MTProtoConstants.prekeyLen
            ])
            let encIV = Data(rnd[
                MTProtoConstants.skipLen + MTProtoConstants.prekeyLen
                ..< MTProtoConstants.skipLen + MTProtoConstants.prekeyLen + MTProtoConstants.ivLen
            ])

            guard let encryptor = try? AESCipher(key: encKey, iv: encIV) else { continue }

            var dcBytes = Data()
            withUnsafeBytes(of: dcIdx.littleEndian) { dcBytes.append(contentsOf: $0) }

            var tailPlain = Data()
            tailPlain.append(contentsOf: protoTag)
            tailPlain.append(dcBytes)
            tailPlain.append(contentsOf: [UInt8.random(in: 0...255), UInt8.random(in: 0...255)])

            guard let encryptedFull = try? encryptor.update(Data(rnd)) else { continue }

            let rndData = Data(rnd)
            var keystreamTail = Data(capacity: 8)
            for i in 56..<64 {
                keystreamTail.append(encryptedFull[encryptedFull.startIndex + i] ^ rndData[rndData.startIndex + i])
            }

            var encryptedTail = Data(capacity: 8)
            for i in 0..<8 {
                encryptedTail.append(tailPlain[tailPlain.startIndex + i] ^ keystreamTail[keystreamTail.startIndex + i])
            }

            var result = Data(rnd)
            result.replaceSubrange(
                result.startIndex.advanced(by: MTProtoConstants.protoTagPos)
                ..< result.startIndex.advanced(by: MTProtoConstants.handshakeLen),
                with: encryptedTail
            )
            return result
        }
    }

    private static func randomFallback(count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            out[i] = UInt8.random(in: 0...255)
        }
        return out
    }
}