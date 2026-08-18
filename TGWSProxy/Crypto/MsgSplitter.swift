import Foundation

/// Splits a TCP stream into individual MTProto transport packets so each can be
/// sent as a separate WebSocket frame. Mirrors Python `MsgSplitter`.
final class MsgSplitter {
    private let dec: AESCipher
    private let proto: UInt32
    private var cipherBuf = Data()
    private var plainBuf = Data()
    private var disabled = false

    init(relayInit: Data, protoInt: UInt32) throws {
        let key = relayInit[
            relayInit.startIndex.advanced(by: 8)
            ..< relayInit.startIndex.advanced(by: 40)
        ]
        let iv = relayInit[
            relayInit.startIndex.advanced(by: 40)
            ..< relayInit.startIndex.advanced(by: 56)
        ]
        let cipher = try AESCipher(key: key, iv: iv)
        try cipher.discard(MTProtoConstants.zero64)
        self.dec = cipher
        self.proto = protoInt
    }

    /// Feeds a ciphertext chunk and returns any complete packets found.
    func split(chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        if disabled { return [chunk] }

        cipherBuf.append(chunk)
        plainBuf.append(try dec.update(chunk))

        var parts: [Data] = []
        var offset = 0
        let bufLen = cipherBuf.count

        while offset < bufLen {
            guard let packetLen = nextPacketLen(offset: offset, avail: bufLen - offset) else {
                break
            }
            if packetLen <= 0 {
                parts.append(Data(cipherBuf[cipherBuf.startIndex + offset...]))
                offset = bufLen
                disabled = true
                break
            }
            parts.append(Data(cipherBuf[
                cipherBuf.startIndex + offset
                ..< cipherBuf.startIndex + offset + packetLen
            ]))
            offset += packetLen
        }

        if offset > 0 {
            cipherBuf.removeFirst(offset)
            plainBuf.removeFirst(offset)
        }
        return parts
    }

    /// Flushes any remaining buffered bytes as a final packet.
    func flush() -> Data? {
        guard !cipherBuf.isEmpty else { return nil }
        let tail = Data(cipherBuf)
        cipherBuf.removeAll()
        plainBuf.removeAll()
        return tail
    }

    private func nextPacketLen(offset: Int, avail: Int) -> Int? {
        guard avail > 0 else { return nil }
        switch proto {
        case MTProtoConstants.protoAbridgedInt:
            return nextAbridgedLen(offset: offset, avail: avail)
        case MTProtoConstants.protoIntermediateInt,
             MTProtoConstants.protoPaddedIntermediateInt:
            return nextIntermediateLen(offset: offset, avail: avail)
        default:
            return 0
        }
    }

    private func nextAbridgedLen(offset: Int, avail: Int) -> Int? {
        let first = plainBuf[plainBuf.startIndex + offset]
        let headerLen: Int
        let payloadLen: Int
        if first == 0x7F || first == 0xFF {
            guard avail >= 4 else { return nil }
            payloadLen = Int(plainBuf.littleEndianUInt32(at: offset + 1) & 0x7FFFFFFF) * 4
            headerLen = 4
        } else {
            payloadLen = Int(first & 0x7F) * 4
            headerLen = 1
        }
        guard payloadLen > 0 else { return 0 }
        let packetLen = headerLen + payloadLen
        guard avail >= packetLen else { return nil }
        return packetLen
    }

    private func nextIntermediateLen(offset: Int, avail: Int) -> Int? {
        guard avail >= 4 else { return nil }
        let payloadLen = Int(plainBuf.littleEndianUInt32(at: offset) & 0x7FFFFFFF)
        guard payloadLen > 0 else { return 0 }
        let packetLen = 4 + payloadLen
        guard avail >= packetLen else { return nil }
        return packetLen
    }
}