import Foundation

/// Constants from the original `proxy/utils.py`.
enum MTProtoConstants {
    static let handshakeLen = 64
    static let skipLen = 8
    static let prekeyLen = 32
    static let keyLen = 32
    static let ivLen = 16
    static let protoTagPos = 56
    static let dcIdxPos = 60

    static let protoTagAbridged: [UInt8] = [0xEF, 0xEF, 0xEF, 0xEF]
    static let protoTagIntermediate: [UInt8] = [0xEE, 0xEE, 0xEE, 0xEE]
    static let protoTagSecure: [UInt8] = [0xDD, 0xDD, 0xDD, 0xDD]

    static let protoAbridgedInt: UInt32 = 0xEFEFEFEF
    static let protoIntermediateInt: UInt32 = 0xEEEEEEEE
    static let protoPaddedIntermediateInt: UInt32 = 0xDDDDDDDD

    static let zero64 = Data(repeating: 0, count: 64)

    static let reservedFirstBytes: Set<UInt8> = [0xEF]
    static let reservedStarts: Set<[UInt8]> = [
        Array("HEAD".utf8),
        Array("POST".utf8),
        Array("GET ".utf8),
        protoTagIntermediate,
        protoTagSecure,
        [0x16, 0x03, 0x01, 0x02],
    ]
    static let reservedContinue: [UInt8] = [0, 0, 0, 0]

    /// Default DC IPs from `utils.py`.
    static let dcDefaultIPs: [Int: String] = [
        1: "149.154.175.50",
        2: "149.154.167.51",
        3: "149.154.175.100",
        4: "149.154.167.91",
        5: "149.154.171.5",
        203: "91.105.192.100",
    ]

    static let dcTestIPs: [Int: String] = [
        1: "149.154.175.10",
        2: "149.154.167.40",
        3: "149.154.175.117",
    ]

    static let wsPath = "/apiws"
    static let wsPathTest = "/apiws_test"

    static let ipFailCooldown: TimeInterval = 3600.0
    static let dcFailCooldown: TimeInterval = 60.0
    static let wsFailTimeout: TimeInterval = 2.0

    /// WebSocket domains for a given DC (kws{dc}.web.telegram.org).
    static func wsDomains(dc: Int, isMedia: Bool) -> [String] {
        var effectiveDC = dc
        if dc == 203 { effectiveDC = 2 }
        if isMedia {
            return ["kws\(effectiveDC)-1.web.telegram.org", "kws\(effectiveDC).web.telegram.org"]
        }
        return ["kws\(effectiveDC).web.telegram.org", "kws\(effectiveDC)-1.web.telegram.org"]
    }
}

/// Data extension helpers used across the crypto layer.
extension Data {
    /// Reverses the byte order (mirrors Python `[::-1]`).
    var reversedBytes: Data {
        Data(reversed())
    }

    /// Reads a little-endian signed Int16 at the given offset.
    func littleEndianInt16(at offset: Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        let slice = self[startIndex.advanced(by: offset)..<startIndex.advanced(by: offset + 2)]
        return slice.withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
    }

    /// Reads a little-endian UInt32 at the given offset.
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let slice = self[startIndex.advanced(by: offset)..<startIndex.advanced(by: offset + 4)]
        return slice.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
}

/// Safe two's-complement signed conversion (Python-style abs on negative dc).
extension Int16 {
    /// Absolute value in Python semantics (returns positive magnitude).
    var pythonAbs: Int {
        Int(self < 0 ? -self : self)
    }
}