import Foundation
import CryptoKit

/// Holds the four incremental AES-CTR cipher states used to bridge
/// the client and Telegram sides. Mirrors Python `CryptoCtx`.
final class CryptoCtx {
    let cltDec: AESCipher   // decrypt data from client
    let cltEnc: AESCipher   // encrypt data to client
    let tgEnc: AESCipher    // encrypt data to telegram
    let tgDec: AESCipher    // decrypt data from telegram

    init(cltDec: AESCipher, cltEnc: AESCipher, tgEnc: AESCipher, tgDec: AESCipher) {
        self.cltDec = cltDec
        self.cltEnc = cltEnc
        self.tgEnc = tgEnc
        self.tgDec = tgDec
    }
}

/// Builds the four crypto contexts from the client handshake prekey/iv,
/// the proxy secret, and the freshly generated relay init.
/// Mirrors Python `_build_crypto_ctx`.
enum CryptoContextBuilder {
    static func build(
        clientDecPrekeyIV: Data,
        secret: Data,
        relayInit: Data
    ) throws -> CryptoCtx {
        // --- client decrypt side: key = SHA256(prekey + secret), iv from handshake
        let cltDecPrekey = clientDecPrekeyIV.prefix(MTProtoConstants.prekeyLen)
        let cltDecIV = clientDecPrekeyIV.dropFirst(MTProtoConstants.prekeyLen)
        let cltDecKey = SHA256.hash(data: cltDecPrekey + secret)
        let cltDecKeyData = Data(cltDecKey)

        // --- client encrypt side: reverse of prekey/iv
        let cltEncPrekeyIV = clientDecPrekeyIV.reversedBytes
        let cltEncKey = SHA256.hash(
            data: cltEncPrekeyIV.prefix(MTProtoConstants.prekeyLen) + secret
        )
        let cltEncKeyData = Data(cltEncKey)
        let cltEncIV = cltEncPrekeyIV.dropFirst(MTProtoConstants.prekeyLen)

        let cltDecryptor = try AESCipher(key: cltDecKeyData, iv: cltDecIV)
        let cltEncryptor = try AESCipher(key: cltEncKeyData, iv: cltEncIV)

        // fast-forward client decryptor past the 64-byte init
        try cltDecryptor.discard(MTProtoConstants.zero64)

        // --- relay side: standard obfuscation (raw key, no secret hash)
        let relayEncKey = relayInit[
            relayInit.startIndex.advanced(by: MTProtoConstants.skipLen)
            ..< relayInit.startIndex.advanced(by: MTProtoConstants.skipLen + MTProtoConstants.prekeyLen)
        ]
        let relayEncIV = relayInit[
            relayInit.startIndex.advanced(by: MTProtoConstants.skipLen + MTProtoConstants.prekeyLen)
            ..< relayInit.startIndex.advanced(by: MTProtoConstants.skipLen + MTProtoConstants.prekeyLen + MTProtoConstants.ivLen)
        ]

        let relayDecPrekeyIV = relayInit[
            relayInit.startIndex.advanced(by: MTProtoConstants.skipLen)
            ..< relayInit.startIndex.advanced(by: MTProtoConstants.skipLen + MTProtoConstants.prekeyLen + MTProtoConstants.ivLen)
        ].reversedBytes
        let relayDecKey = relayDecPrekeyIV.prefix(MTProtoConstants.keyLen)
        let relayDecIV = relayDecPrekeyIV.dropFirst(MTProtoConstants.keyLen)

        let tgEncryptor = try AESCipher(key: relayEncKey, iv: relayEncIV)
        let tgDecryptor = try AESCipher(key: relayDecKey, iv: relayDecIV)

        // fast-forward tg encryptor past the 64-byte init
        try tgEncryptor.discard(MTProtoConstants.zero64)

        return CryptoCtx(
            cltDec: cltDecryptor,
            cltEnc: cltEncryptor,
            tgEnc: tgEncryptor,
            tgDec: tgDecryptor
        )
    }
}