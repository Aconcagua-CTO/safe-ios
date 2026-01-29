//
//  UInt256.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 15.06.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation

#if canImport(BigInt)
import BigInt

typealias UInt256 = BigUInt
typealias Int256 = BigInt

extension UInt256 {
    var data32: Data {
        Data(ethHex: String(self, radix: 16)).leftPadded(to: 32).suffix(32)
    }
}

#else

/// Lightweight `UInt256` for targets that don't link `BigInt` (e.g. extensions).
/// It supports decoding/encoding and basic string/data conversions.
struct UInt256: Hashable, Codable, CustomStringConvertible {
    private var magnitudeBE: Data // big-endian, 0...32 bytes, no guarantee of length

    init<T>(_ value: T) where T: BinaryInteger {
        if value == 0 {
            self.magnitudeBE = Data()
            return
        }
        // Convert BinaryInteger -> bytes (little endian via shifting)
        var v = value
        var bytesLE: [UInt8] = []
        while v > 0 {
            let byte = UInt8(truncatingIfNeeded: v)
            bytesLE.append(byte)
            v >>= 8
        }
        self.magnitudeBE = Data(bytesLE.reversed()).suffix(32)
    }

    init(_ data: Data) {
        // Keep least-significant 32 bytes if longer.
        self.magnitudeBE = data.suffix(32)
    }

    init?(_ decimalString: String) {
        let trimmed = decimalString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.allSatisfy({ $0.isNumber }) else { return nil }
        // Convert decimal string -> bytes via repeated division by 256.
        var digits = trimmed.compactMap { Int(String($0)) }
        // Normalize leading zeros
        while digits.count > 1, digits.first == 0 { digits.removeFirst() }

        if digits.count == 1, digits[0] == 0 {
            self.magnitudeBE = Data()
            return
        }

        var bytesLE: [UInt8] = []
        while !(digits.count == 1 && digits[0] == 0) {
            var newDigits: [Int] = []
            newDigits.reserveCapacity(digits.count)
            var carry = 0
            for d in digits {
                let num = carry * 10 + d
                let q = num / 256
                carry = num % 256
                if !newDigits.isEmpty || q != 0 { newDigits.append(q) }
            }
            bytesLE.append(UInt8(carry))
            digits = newDigits.isEmpty ? [0] : newDigits
            if bytesLE.count > 32 {
                // overflow for UInt256, keep least-significant 32 bytes
                break
            }
        }

        self.magnitudeBE = Data(bytesLE.reversed()).suffix(32)
    }

    var data32: Data {
        magnitudeBE.leftPadded(to: 32).suffix(32)
    }

    var description: String {
        // Convert bytes -> decimal string via repeated *256 + byte.
        let bytes = [UInt8](data32)
        var digits: [Int] = [0]
        for b in bytes {
            var carry = Int(b)
            for i in stride(from: digits.count - 1, through: 0, by: -1) {
                let val = digits[i] * 256 + carry
                digits[i] = val % 10
                carry = val / 10
            }
            while carry > 0 {
                digits.insert(carry % 10, at: 0)
                carry /= 10
            }
        }
        // Trim leading zeros
        while digits.count > 1, digits.first == 0 { digits.removeFirst() }
        return digits.map(String.init).joined()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            if string.hasPrefix("0x") || string.hasPrefix("0X") {
                let data = Data(ethHex: string)
                self.init(data)
            } else if let v = UInt256(string) {
                self = v
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UInt256 string")
            }
        } else if let uint = try? container.decode(UInt.self) {
            self.init(uint)
        } else if let int = try? container.decode(Int.self), int >= 0 {
            self.init(int)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UInt256 value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

#endif
