// SPDX-License-Identifier: GPL-3.0-only

import XCTest

@testable import MiBudsCore

final class ProtocolTests: XCTestCase {
    func hex(_ text: String) -> [UInt8] {
        let chars = Array(text)
        return stride(from: 0, to: chars.count, by: 2).map {
            UInt8(String(chars[$0...($0 + 1)]), radix: 16)!
        }
    }
    func testFragmentedAndCoalescedFrames() {
        let packet = Packet(flags: 4, opcode: 0xf3, payload: [0, 0xa0, 3, 0, 7, 5])
        for split in 0...packet.bytes.count {
            var parser = StreamParser()
            let first = parser.feed([7, 8] + Array(packet.bytes.prefix(split)))
            let second = parser.feed(Array(packet.bytes.dropFirst(split)) + packet.bytes)
            XCTAssertEqual(first + second, [packet, packet])
        }
    }
    func testMalformedFramingResynchronizes() {
        var parser = StreamParser()
        let packet = Packet(flags: 4, opcode: 2, payload: [0, 1])
        XCTAssertEqual(parser.feed([0xfe, 0xdc, 0xba, 4, 2, 255, 255] + packet.bytes), [packet])
    }
    func testConfigAndGestureValidation() throws {
        XCTAssertEqual(try BudsCodec.records([3, 0, 7, 5, 3, 0, 47, 1]), [7: [5], 47: [1]])
        XCTAssertThrowsError(try BudsCodec.records([3, 0, 7]))
        XCTAssertThrowsError(try BudsCodec.records([3, 0, 7, 5, 3, 0, 7, 1]))
        XCTAssertEqual(try BudsCodec.gestures([1, 1, 3, 3, 0, 8]), [1: [1, 3], 3: [0, 8]])
        XCTAssertThrowsError(try BudsCodec.gestures([1, 1]))
        XCTAssertThrowsError(try BudsCodec.gestures([1, 1, 2, 1, 3, 4]))
    }
    func testBatteryValues() {
        let levels = BudsCodec.batteries(in: [9, 2, 2, 4, 7, 70, 228, 255])!
        XCTAssertEqual(levels[0].percent, 70)
        XCTAssertEqual(levels[1].percent, 100)
        XCTAssertTrue(levels[1].charging)
        XCTAssertNil(levels[2].percent)
        XCTAssertEqual(Battery(0).percent, 0)
        XCTAssertNil(Battery(127).percent)
    }
    func testWriteMatchesUpstreamWireFormat() {
        XCTAssertEqual(
            BudsCodec.write(47, value: [1], counter: 0x90), hex("fedcbac4f200059003002f01ef"))
        XCTAssertEqual(
            BudsCodec.write(2, value: [1, 3, 255], counter: 0xa0),
            hex("fedcbac4f20007a00500020103ffef"))
    }
    func testPublishedCipherVectors() {
        let vectors = [
            ("9762e8a1836d32cc4b7b8605c553545f", "f7fe2d0211bab715efe4c33ac740574d"),
            ("9ddc4d55a9f74b1c2df9d11a2762b281", "ac0512878403a24c87d1b6cb974061c9"),
            ("a979ae189a0c36bf973de72297ed1595", "7b09a3799fa3005472c2673c9c45e82b"),
            ("57990d37d3dad961ee7e6a092ba4f2ef", "6b21b2bdd693d3147ee9e6f41e46eb87"),
            ("60c881a805416aeeaa3a1e079d879568", "787748b987ecf34ab33464eaa78f44ba"),
        ]
        for (challenge, answer) in vectors {
            XCTAssertEqual(SaferPlus.response(hex(challenge)), hex(answer))
        }
    }
    func testCommandMutualAuthenticationAndPartialNormalTail() throws {
        let auth = Authentication(mode: .command)
        var sent: [[UInt8]] = []
        auth.send = { sent.append($0) }
        try auth.start()
        var parser = StreamParser()
        let initial = parser.feed(sent[0])[0]
        let answer = SaferPlus.response(Array(initial.payload.dropFirst(2)))
        let reply = Packet(flags: 4, opcode: 0x50, payload: [0, initial.payload[0], 1] + answer)
            .bytes
        XCTAssertEqual(try auth.feed(reply), [])
        XCTAssertFalse(auth.ready)
        let challenge = hex("9762e8a1836d32cc4b7b8605c553545f")
        _ = try auth.feed(Packet(flags: 0xc7, opcode: 0x50, payload: [9, 1] + challenge).bytes)
        let response = parser.feed(sent.last!)[0]
        XCTAssertEqual(response.payload, [0, 9, 1] + SaferPlus.response(challenge))
        let normal = Packet(flags: 4, opcode: 0xf3, payload: [0, 0xa0, 3, 0, 7, 5]).bytes
        let tail = Array(normal.prefix(5))
        XCTAssertEqual(
            try auth.feed(Packet(flags: 0xc7, opcode: 0x51, payload: [10, 1, 0]).bytes + tail), tail
        )
        XCTAssertTrue(auth.ready)
    }
    func testRawMutualAuthenticationWithFragmentation() throws {
        let auth = Authentication(mode: .raw)
        var sent: [[UInt8]] = []
        auth.send = { sent.append($0) }
        try auth.start()
        // The first raw challenge is deliberately delayed to match upstream timing.
        Thread.sleep(forTimeInterval: 0.52)
        try auth.tick()
        let answer = [UInt8(1)] + SaferPlus.response(Array(sent[0].dropFirst()))
        _ = try auth.feed(Array(answer.prefix(4)))
        _ = try auth.feed(Array(answer.dropFirst(4)))
        XCTAssertEqual(sent.last!, [2, 0x70, 0x61, 0x73, 0x73])
        let challenge = [UInt8](0..<16)
        _ = try auth.feed([0] + challenge)
        XCTAssertEqual(sent.last!, [1] + SaferPlus.response(challenge))
        let tail: [UInt8] = [0xfe, 0xdc, 0xba]
        XCTAssertEqual(try auth.feed([2, 0x70, 0x61, 0x73, 0x73] + tail), tail)
        XCTAssertTrue(auth.ready)
    }
    func testAuthFailureNeverMakesSessionReady() throws {
        let auth = Authentication(mode: .command)
        auth.send = { _ in }
        try auth.start()
        XCTAssertThrowsError(
            try auth.feed(
                Packet(
                    flags: 4, opcode: 0x50, payload: [0, 0, 1] + [UInt8](repeating: 0, count: 16)
                ).bytes))
        XCTAssertFalse(auth.ready)
    }
}
