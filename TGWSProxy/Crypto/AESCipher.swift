import Foundation
import CommonCrypto

/// A thin AES-256-CTR stream cipher wrapper around CommonCrypto.
/// It behaves like an incremental encryptor/decryptor, matching the Python
/// `Cipher(algorithms.AES(key), modes.CTR(iv)).encryptor()` semantics.
final class AESCipher {
    private var cryptor: CCCryptorRef?
    private let key: Data
    private let iv: Data

    init(key: Data, iv: Data) throws {
        guard key.count == 32 else {
            throw CryptoError.invalidKey
        }
        guard iv.count == 16 else {
            throw CryptoError.invalidIV
        }
        self.key = key
        self.iv = iv
        try reset()
    }

    func reset() throws {
        close()
        var ref: CCCryptorRef?
        let status = CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            [UInt8](iv),
            [UInt8](key),
            key.count,
            nil,
            0,
            0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &ref
        )
        guard status == kCCSuccess, let ref else {
            throw CryptoError.cryptorInit(status)
        }
        self.cryptor = ref
    }

    /// Encrypt (or decrypt, since CTR is symmetric) a chunk of data,
    /// advancing the internal keystream state.
    func update(_ data: Data) throws -> Data {
        guard let cryptor else { throw CryptoError.closed }
        let outputLength = data.count + 32
        var output = [UInt8](repeating: 0, count: outputLength)
        var moved: Int = 0

        let status = CCCryptorUpdate(
            cryptor,
            [UInt8](data),
            data.count,
            &output,
            outputLength,
            &moved
        )
        guard status == kCCSuccess else {
            throw CryptoError.update(status)
        }
        return Data(output.prefix(moved))
    }

    /// Run a chunk through the cipher and discard the result,
    /// used to fast-forward the keystream past zero-filled blocks.
    func discard(_ data: Data) throws {
        _ = try update(data)
    }

    func close() {
        if let cryptor {
            CCCryptorRelease(cryptor)
        }
        cryptor = nil
    }

    deinit {
        close()
    }

    /// Builds a zero-filled Data of the given length.
    static func zero(_ count: Int) -> Data {
        Data(repeating: 0, count: count)
    }
}

enum CryptoError: LocalizedError {
    case invalidKey
    case invalidIV
    case cryptorInit(Int32)
    case update(Int32)
    case closed

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid AES key length (must be 32 bytes)"
        case .invalidIV: return "Invalid AES IV length (must be 16 bytes)"
        case .cryptorInit(let s): return "AES cryptor init failed with status \(s)"
        case .update(let s): return "AES update failed with status \(s)"
        case .closed: return "AES cryptor is closed"
        }
    }
}