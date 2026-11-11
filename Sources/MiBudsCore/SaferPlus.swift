// SPDX-License-Identifier: GPL-3.0-only

// Swift translation of MiBudsClient / LeandroPG19/Buds SAFER+ variant, GPL-3.0.
import Foundation

public enum SaferPlus {
    private static let coefficients: [[Int]] = [
        [2, 1, 1, 1, 4, 2, 1, 1, 2, 2, 4, 2, 4, 4, 16, 8],
        [2, 1, 1, 1, 4, 2, 1, 1, 1, 1, 2, 1, 2, 2, 8, 4],
        [1, 1, 4, 2, 2, 2, 4, 2, 16, 8, 4, 4, 2, 1, 1, 1],
        [1, 1, 4, 2, 1, 1, 2, 1, 8, 4, 2, 2, 2, 1, 1, 1],
        [16, 8, 2, 2, 4, 2, 4, 4, 1, 1, 4, 2, 1, 1, 2, 1],
        [8, 4, 1, 1, 2, 1, 2, 2, 1, 1, 4, 2, 1, 1, 2, 1],
        [2, 2, 4, 2, 4, 4, 16, 8, 2, 1, 1, 1, 4, 2, 1, 1],
        [1, 1, 2, 1, 2, 2, 8, 4, 2, 1, 1, 1, 4, 2, 1, 1],
        [4, 2, 4, 4, 16, 8, 2, 2, 1, 1, 2, 1, 1, 1, 4, 2],
        [2, 1, 2, 2, 8, 4, 1, 1, 1, 1, 2, 1, 1, 1, 4, 2],
        [4, 4, 16, 8, 1, 1, 2, 1, 4, 2, 1, 1, 4, 2, 2, 2],
        [2, 2, 8, 4, 1, 1, 2, 1, 4, 2, 1, 1, 2, 1, 1, 1],
        [1, 1, 2, 1, 1, 1, 4, 2, 4, 4, 16, 8, 2, 2, 4, 2],
        [1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 8, 4, 1, 1, 2, 1],
        [4, 2, 1, 1, 2, 1, 1, 1, 4, 2, 2, 2, 16, 8, 4, 4],
        [4, 2, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 8, 4, 2, 2],
    ]
    private static func power(_ exponent: Int) -> Int {
        var value = 1
        for _ in 0..<exponent { value = value * 45 % 257 }
        return value
    }
    private static let exp = (0..<256).map { power($0) % 256 }
    private static let log: [Int] = {
        var table = [Int](repeating: 0, count: 256)
        for i in 0..<256 { table[exp[i]] = i }
        return table
    }()
    private static let bias = (0..<16).map { i in
        (0..<16).map { j in power(power(17 * (i + 2) + j + 1)) % 256 }
    }
    private static func xor(_ i: Int) -> Bool { (0x9999 & (1 << i)) != 0 }
    private static func combine(_ a: Int, _ b: Int, _ i: Int) -> Int {
        xor(i) ? a ^ b : (a + b) & 255
    }
    public static func response(_ challenge: [UInt8]) -> [UInt8] {
        precondition(challenge.count == 16)
        var first = challenge.map(Int.init)
        first[15] ^= 6
        var register = first + [first.reduce(0, ^)]
        var keys = [first]
        for k in 1...16 {
            register = register.map { (($0 << 3) | ($0 >> 5)) & 255 }
            keys.append((0..<16).map { (register[(k + $0) % 17] + bias[k - 1][$0]) & 255 })
        }
        let plain = [
            0x11, 0x22, 0x33, 0x33, 0x22, 0x11, 0x11, 0x22, 0x33, 0x33, 0x22, 0x11, 0x11, 0x22,
            0x33, 0x33,
        ]
        var block = plain
        for round in 0..<8 {
            if round == 2 { block = (0..<16).map { combine(block[$0], plain[$0], $0) } }
            block = (0..<16).map { combine(block[$0], keys[2 * round][$0], $0) }
            block = (0..<16).map { xor($0) ? exp[block[$0]] : log[block[$0]] }
            block = (0..<16).map {
                xor($0)
                    ? (keys[2 * round + 1][$0] + block[$0]) & 255
                    : keys[2 * round + 1][$0] ^ block[$0]
            }
            block = (0..<16).map { i in
                (0..<16).reduce(0) { $0 + coefficients[i][$1] * block[$1] } & 255
            }
        }
        return (0..<16).map { UInt8(combine(block[$0], keys[16][$0], $0)) }
    }
}
