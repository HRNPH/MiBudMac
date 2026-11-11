// SPDX-License-Identifier: GPL-3.0-only

// Service-specific mutual authentication, translated from MiBudsClient. GPL-3.0.
import Foundation

public final class Authentication {
    public enum Mode { case command, raw }
    public private(set) var ready = false
    private let mode: Mode
    private var stage = 0
    private var parser = StreamParser()
    private var buffer: [UInt8] = []
    private let expected: [UInt8]
    private var sequence: UInt8 = 0
    private var pending: [UInt8: (UInt8, [UInt8], Date, Int)] = [:]
    private let deadline: Date
    private let challenge: [UInt8]
    private var nextRaw: Date
    private var rawAttempts = 0
    public var send: (([UInt8]) throws -> Void)?

    public init(mode: Mode) {
        self.mode = mode
        challenge = (0..<16).map { _ in UInt8.random(in: 0...255) }
        expected = SaferPlus.response(challenge)
        deadline = Date().addingTimeInterval(mode == .raw ? 9.5 : 25)
        nextRaw = Date().addingTimeInterval(0.5)
    }
    public func start() throws {
        if mode == .command { try request(0x50, [1] + challenge) }
    }
    private func request(_ opcode: UInt8, _ data: [UInt8]) throws {
        let seq = sequence
        sequence &+= 1
        let bytes = Packet(flags: 0xc4, opcode: opcode, payload: [seq] + data).bytes
        pending[seq] = (opcode, bytes, Date().addingTimeInterval(opcode == 0x50 ? 2 : 12), 0)
        try send?(bytes)
    }
    public func tick() throws {
        guard !ready else { return }
        guard Date() < deadline else { throw BudsError.timeout }
        if mode == .raw, stage == 0, rawAttempts < 3, Date() >= nextRaw {
            rawAttempts += 1
            nextRaw = Date().addingTimeInterval(3)
            try send?([0] + challenge)
        }
        for (seq, entry) in pending where Date() >= entry.2 {
            guard entry.3 < 3 else { throw BudsError.timeout }
            pending[seq] = (
                entry.0, entry.1, Date().addingTimeInterval(entry.0 == 0x50 ? 2 : 12), entry.3 + 1
            )
            try send?(entry.1)
        }
    }
    public func feed(_ bytes: [UInt8]) throws -> [UInt8] {
        guard !ready else { return bytes }
        try tick()
        if mode == .raw {
            buffer += bytes
            while !buffer.isEmpty {
                let kind: UInt8 = stage == 0 ? 1 : stage == 1 ? 0 : 2
                guard buffer[0] == kind else { throw BudsError.invalidPacket }
                let size = kind == 2 ? 5 : 17
                guard buffer.count >= size else { return [] }
                let message = Array(buffer.prefix(size))
                buffer.removeFirst(size)
                if stage == 0 {
                    guard Array(message.dropFirst()) == expected else {
                        throw BudsError.unconfirmed
                    }
                    stage = 1
                    try send?([2, 0x70, 0x61, 0x73, 0x73])
                } else if stage == 1 {
                    stage = 2
                    try send?([1] + SaferPlus.response(Array(message.dropFirst())))
                } else {
                    guard message == [2, 0x70, 0x61, 0x73, 0x73] else {
                        throw BudsError.unconfirmed
                    }
                    ready = true
                    let tail = buffer
                    buffer = []
                    return tail
                }
            }
            return []
        }
        var normal: [UInt8] = []
        for packet in parser.feed(bytes) {
            if ready {
                normal += packet.bytes
                continue
            }
            guard [0x50, 0x51].contains(packet.opcode), [4, 7].contains(packet.flags & 7) else {
                continue
            }
            let request = packet.flags & 0x80 != 0
            guard packet.payload.count >= (request ? 1 : 2) else { throw BudsError.invalidPacket }
            let seq = packet.payload[request ? 0 : 1]
            let data = Array(packet.payload.dropFirst(request ? 1 : 2))
            if !request {
                guard let entry = pending[seq], entry.0 == packet.opcode else { continue }
                guard packet.payload[0] == 0 else { throw BudsError.rejected(packet.payload[0]) }
                pending[seq] = nil
                if packet.opcode == 0x51 {
                    guard data == [1] else { throw BudsError.invalidPacket }
                    continue
                }
                guard stage == 0, data == [1] + expected else { throw BudsError.unconfirmed }
                stage = 1
                try self.request(0x51, [1, 0])
            } else if packet.opcode == 0x50 {
                guard stage == 1, data.count == 17, data[0] == 1 else {
                    throw BudsError.invalidPacket
                }
                stage = 2
                try send?(
                    Packet(
                        flags: 4, opcode: 0x50,
                        payload: [0, seq, 1] + SaferPlus.response(Array(data.dropFirst()))
                    ).bytes)
            } else {
                guard stage == 2, data.count == 2, data[0] == 1 else {
                    throw BudsError.invalidPacket
                }
                try send?(Packet(flags: 4, opcode: 0x51, payload: [0, seq, 1]).bytes)
                guard data[1] == 0 else { throw BudsError.rejected(data[1]) }
                ready = true
                pending = [:]
            }
        }
        if ready { normal += parser.takeBuffer() }
        return normal
    }
}
