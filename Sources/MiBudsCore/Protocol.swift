// SPDX-License-Identifier: GPL-3.0-only

// Swift port of the MiBudsClient RCSP protocol. GPL-3.0; see CREDITS.md.
import Foundation

public enum BudsError: LocalizedError {
    case invalidPacket, disconnected, timeout
    case rejected(UInt8)
    case unconfirmed
    public var errorDescription: String? {
        switch self {
        case .invalidPacket: return "The earbuds returned an incomplete or invalid response."
        case .disconnected:
            return "The earbud control connection is closed. Reconnect to try again."
        case .timeout: return "The earbuds did not respond. Close other earbud apps and reconnect."
        case .rejected(let code): return "The earbuds rejected the request (\(code))."
        case .unconfirmed: return "The earbuds did not confirm the change. Refresh and try again."
        }
    }
}

public struct Packet: Equatable {
    public let flags: UInt8
    public let opcode: UInt8
    public let payload: [UInt8]
    public init(flags: UInt8, opcode: UInt8, payload: [UInt8]) {
        self.flags = flags
        self.opcode = opcode
        self.payload = payload
    }
    public var bytes: [UInt8] {
        [0xfe, 0xdc, 0xba, flags, opcode, UInt8(payload.count >> 8), UInt8(payload.count & 255)]
            + payload + [0xef]
    }
}

public struct StreamParser {
    private var buffer: [UInt8] = []
    public init() {}
    public mutating func takeBuffer() -> [UInt8] {
        let tail = buffer
        buffer = []
        return tail
    }
    public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
        buffer += bytes
        var packets: [Packet] = []
        while !buffer.isEmpty {
            guard
                let start = buffer.indices.first(where: {
                    $0 + 2 < buffer.count && Array(buffer[$0...($0 + 2)]) == [0xfe, 0xdc, 0xba]
                })
            else {
                buffer = Array(buffer.suffix(2))
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 7 else { break }
            let count = Int(buffer[5]) * 256 + Int(buffer[6])
            // RCSP settings are small; bound malformed peer input.
            guard count <= 4096 else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= count + 8 else { break }
            guard buffer[count + 7] == 0xef else {
                buffer.removeFirst()
                continue
            }
            packets.append(
                Packet(flags: buffer[3], opcode: buffer[4], payload: Array(buffer[7..<(7 + count)]))
            )
            buffer.removeFirst(count + 8)
        }
        return packets
    }
}

public struct Battery: Equatable {
    public let percent: Int?
    public let charging: Bool
    public init(_ raw: UInt8) {
        let level = Int(raw & 0x7f)
        percent = (0...100).contains(level) && raw != 255 ? level : nil
        charging = raw & 0x80 != 0 && percent != nil
    }
}

public enum BudsCodec {
    public static func request(opcode: UInt8, counter: UInt8, body: [UInt8]) -> [UInt8] {
        Packet(flags: 0xc4, opcode: opcode, payload: [counter] + body).bytes
    }
    public static func read(_ config: UInt16, counter: UInt8) -> [UInt8] {
        request(opcode: 0xf3, counter: counter, body: [UInt8(config >> 8), UInt8(config & 255)])
    }
    public static func write(_ config: UInt16, value: [UInt8], counter: UInt8) -> [UInt8] {
        request(
            opcode: 0xf2, counter: counter,
            body: [UInt8(value.count + 2), UInt8(config >> 8), UInt8(config & 255)] + value)
    }
    public static func records(_ bytes: [UInt8]) throws -> [UInt16: [UInt8]] {
        var result: [UInt16: [UInt8]] = [:]
        var pos = 0
        while pos < bytes.count {
            let count = Int(bytes[pos])
            let end = pos + 1 + count
            guard count >= 2, end <= bytes.count else { throw BudsError.invalidPacket }
            let key = UInt16(bytes[pos + 1]) << 8 | UInt16(bytes[pos + 2])
            guard result[key] == nil else { throw BudsError.invalidPacket }
            result[key] = Array(bytes[(pos + 3)..<end])
            pos = end
        }
        return result
    }
    public static func batteries(in payload: [UInt8]) -> [Battery]? {
        guard payload.count >= 7 else { return nil }
        for pos in 0...(payload.count - 7) where Array(payload[pos..<(pos + 4)]) == [2, 2, 4, 7] {
            return payload[(pos + 4)..<(pos + 7)].map(Battery.init)
        }
        return nil
    }
    public static let profiles: [(id: UInt8, name: String, detail: String, symbol: String)] = [
        (0, "Standard", "Default sound profile", "waveform"),
        (6, "Treble", "Increase high frequencies", "sparkles"),
        (5, "Bass", "Increase low frequencies", "speaker.wave.2"),
        (1, "Voice", "Emphasize speech and vocals", "mic"),
        (7, "Volume", "Increase loudness", "speaker.plus"),
    ]
    public static let gestureNames: [(id: UInt8, name: String)] = [
        (4, "Single tap"), (1, "Double tap"), (2, "Triple tap"), (3, "Press and hold"),
    ]
    public static let actions: [UInt8: String] = [
        0: "Voice assistant", 1: "Play / pause", 2: "Previous track", 3: "Next track",
        4: "Volume up", 5: "Volume down", 8: "Unassigned", 9: "Take photo",
    ]
    public static func allowedActions(_ gesture: UInt8) -> [UInt8] {
        switch gesture {
        case 4: return [8, 1, 4, 5, 2, 3, 9]
        case 1: return [1, 4, 5, 2, 3, 8]
        case 2: return [3, 2, 1, 4, 5, 8]
        case 3: return [0, 9, 8]
        default: return []
        }
    }
    public static func gestures(_ value: [UInt8]) throws -> [UInt8: [UInt8]] {
        guard value.count.isMultiple(of: 3) else { throw BudsError.invalidPacket }
        var result: [UInt8: [UInt8]] = [:]
        for i in stride(from: 0, to: value.count, by: 3) {
            guard result[value[i]] == nil else { throw BudsError.invalidPacket }
            result[value[i]] = [value[i + 1], value[i + 2]]
        }
        return result
    }
}
