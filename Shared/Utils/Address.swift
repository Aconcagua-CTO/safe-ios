//
//  Address.swift
//  Multisig
//
//  Created by Dmitry Bespalov on 22.04.20.
//  Copyright © 2020 Gnosis Ltd. All rights reserved.
//

import Foundation
import UIKit

#if canImport(SafeWeb3)
import SafeWeb3
#endif

#if canImport(SafeWeb3)

struct Address: Hashable, ExpressibleByStringInterpolation, CustomStringConvertible, Identifiable {
    var prefix: String?
    fileprivate var _store: EthereumAddress

    init(exactly data: Data) {
        _store = try! EthereumAddress(data)
    }

    init?(_ data: Data) {
        guard let v = try? EthereumAddress(data) else { return nil }
        _store = v
    }

    init(exactly value: String) {
        try! self.init(from: value)
    }

    init?(_ value: String) {
        try? self.init(from: value)
    }

    init(from value: String) throws {
        var text = value
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            text.removeFirst(2)
        }
        let isMixedCase = !(text == text.lowercased() || text == text.uppercased())
        let checkEip55Conformance = isMixedCase
        _store = try EthereumAddress(hex: value, eip55: checkEip55Conformance)
    }

    init(exactly value: UInt256) {
        let data =  Data(ethHex: String(value, radix: 16)).endTruncated(to: 20).leftPadded(to: 20)
        self.init(exactly: data)
    }

    init?(_ value: UInt256) {
        let data = Data(ethHex: String(value, radix: 16)).endTruncated(to: 20).leftPadded(to: 20)
        guard let v = try? EthereumAddress(hex: data.toHexStringWithPrefix(), eip55: false) else { return nil }
        _store = v
    }
    
    init(_ ethereumAddress: EthereumAddress) {
        _store = ethereumAddress
    }

    var id: String {
        return checksummed
    }

    var checksummed: String {
        _store.hex(eip55: true)
    }

    var checksummedWithoutPrefix: String {
        String(checksummed.dropFirst(2))
    }

    var hexadecimal: String {
        _store.hex(eip55: false)
    }

    func ellipsized(prefix: Int = 6, suffix: Int = 4, checksummed: Bool = true) -> String {
        let value = checksummed ? self.checksummed : self.hexadecimal
        return value.prefix(prefix) + "…" + value.suffix(suffix)
    }

    var data: Data {
        Data(_store.rawAddress)
    }

    var data32: Data {
        Data(repeating: 0, count: 32 - data.count) + data
    }

    var count: Int {
        _store.rawAddress.count
    }

    static let zero = Self(exactly: Data(repeating: 0, count: 20))
    static let nativeCoin = Self.zero

    var isZero: Bool {
        self == .zero
    }

    init(stringLiteral value: StringLiteralType) {
        self.init(exactly: value)
    }

    var description: String {
        checksummed
    }

    var truncatedInMiddle: String {
        hexadecimal.prefix(6) + "…" + hexadecimal.suffix(4)
    }

    // This will check if ERC681 or EIP3770
    static func addressWithPrefix(text: String) throws -> Address {
        let (prefix, addressString) = addressWithPrefix(text)
        var address = try Address.init(from: addressString)
        address.prefix = prefix
        return address
    }

    private static func addressWithPrefix(_ string: String) -> (prefix: String?, address: String) {
        var prefix: String?
        var withoutScheme: String
        let hexPrefix = "0x"
        let ethereumPayPrefix = "ethereum:pay-"
        let ethereumPrefix = "ethereum:"

        // We don't need to save the prefix of ERC681 for now, only the EIP3770
        if string.hasPrefix(ethereumPayPrefix) {
            withoutScheme = string.replacingOccurrences(of: ethereumPayPrefix, with: "")
        } else if string.hasPrefix(ethereumPrefix) {
            withoutScheme = string.replacingOccurrences(of: ethereumPrefix, with: "")
        } else if string.contains(":") {
            let components = string.components(separatedBy: ":")
            prefix = components.count == 2 ? components.first! : nil
            withoutScheme = components.last!
        } else {
            withoutScheme = string
        }

        let hasPrefix = withoutScheme.hasPrefix(hexPrefix)
        let withoutPrefix = hasPrefix ? String(withoutScheme.dropFirst(hexPrefix.count)) : withoutScheme
        let leadingHexChars = withoutPrefix.filter { (c) -> Bool in
            return !c.unicodeScalars.contains(where: { !CharacterSet.hexadecimals.contains($0)})
        }

        return (prefix, hexPrefix + leadingHexChars)
    }
}

extension EthereumAddress.Error: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .addressMalformed:
            return "The address is malformed. Please provide an Ethereum address."
        case .checksumWrong:
            return "The address is typed incorrectly. Please double-check it."
        }
    }
}

#else

// Lightweight `Address` implementation for targets where `SafeWeb3` isn't linked
// (e.g. Notification Service Extension). This preserves the subset of behavior
// required by shared models without pulling in web3 dependencies.
struct Address: Hashable, ExpressibleByStringInterpolation, CustomStringConvertible, Identifiable {
    enum Error: Swift.Error, LocalizedError {
        case invalidHexAddress
        case invalidLength

        var errorDescription: String? {
            switch self {
            case .invalidHexAddress:
                return "The address is malformed. Please provide an Ethereum address."
            case .invalidLength:
                return "The address has an invalid length. Please provide an Ethereum address."
            }
        }
    }

    var prefix: String?
    private var raw: Data // 20 bytes

    init(exactly data: Data) {
        precondition(data.count == 20, "Address data must be 20 bytes")
        raw = data
    }

    init?(_ data: Data) {
        guard data.count == 20 else { return nil }
        raw = data
    }

    init(exactly value: String) {
        try! self.init(from: value)
    }

    init?(_ value: String) {
        try? self.init(from: value)
    }

    init(from value: String) throws {
        var text = value
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            text.removeFirst(2)
        }
        guard text.rangeOfCharacter(from: CharacterSet.hexadecimals.inverted) == nil else {
            throw Error.invalidHexAddress
        }
        guard text.count == 40 else {
            throw Error.invalidLength
        }
        let data = Data(hexWC: text)
        guard data.count == 20 else { throw Error.invalidLength }
        raw = data
    }

    init(exactly value: UInt256) {
        let data = Data(value.data32.suffix(20))
        self.init(exactly: data)
    }

    init?(_ value: UInt256) {
        let data = Data(value.data32.suffix(20))
        self.init(data)
    }

    var id: String { checksummed }

    // No EIP-55 checksum generation in the lightweight version; return normalized lowercase hex.
    var checksummed: String { hexadecimal }

    var checksummedWithoutPrefix: String {
        String(checksummed.dropFirst(2))
    }

    var hexadecimal: String {
        raw.toHexStringWithPrefix()
    }

    func ellipsized(prefix: Int = 6, suffix: Int = 4, checksummed: Bool = true) -> String {
        let value = checksummed ? self.checksummed : self.hexadecimal
        return value.prefix(prefix) + "…" + value.suffix(suffix)
    }

    var data: Data { raw }

    var data32: Data {
        Data(repeating: 0, count: 32 - data.count) + data
    }

    var count: Int { raw.count }

    static let zero = Self(exactly: Data(repeating: 0, count: 20))
    static let nativeCoin = Self.zero

    var isZero: Bool { self == .zero }

    init(stringLiteral value: StringLiteralType) {
        self.init(exactly: value)
    }

    var description: String { checksummed }

    var truncatedInMiddle: String {
        hexadecimal.prefix(6) + "…" + hexadecimal.suffix(4)
    }

    static func addressWithPrefix(text: String) throws -> Address {
        let (prefix, addressString) = addressWithPrefix(text)
        var address = try Address.init(from: addressString)
        address.prefix = prefix
        return address
    }

    private static func addressWithPrefix(_ string: String) -> (prefix: String?, address: String) {
        var prefix: String?
        var withoutScheme: String
        let hexPrefix = "0x"
        let ethereumPayPrefix = "ethereum:pay-"
        let ethereumPrefix = "ethereum:"

        if string.hasPrefix(ethereumPayPrefix) {
            withoutScheme = string.replacingOccurrences(of: ethereumPayPrefix, with: "")
        } else if string.hasPrefix(ethereumPrefix) {
            withoutScheme = string.replacingOccurrences(of: ethereumPrefix, with: "")
        } else if string.contains(":") {
            let components = string.components(separatedBy: ":")
            prefix = components.count == 2 ? components.first! : nil
            withoutScheme = components.last!
        } else {
            withoutScheme = string
        }

        let hasPrefix = withoutScheme.hasPrefix(hexPrefix)
        let withoutPrefix = hasPrefix ? String(withoutScheme.dropFirst(hexPrefix.count)) : withoutScheme
        let leadingHexChars = withoutPrefix.filter { c in
            !c.unicodeScalars.contains(where: { !CharacterSet.hexadecimals.contains($0) })
        }

        return (prefix, hexPrefix + leadingHexChars)
    }
}

#endif
