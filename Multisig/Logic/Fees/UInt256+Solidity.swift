//
//  UInt256+Solidity.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation
import BigInt
import Solidity

extension UInt256 {
    init(sol value: Sol.UInt256) {
        self.init(value.encode())
    }
}

extension Sol.UInt256 {
    init(_ value: UInt256) {
        guard let converted = Sol.UInt256(value.description, radix: 10) else {
            preconditionFailure("Failed to convert UInt256 to Sol.UInt256")
        }
        self = converted
    }
}

extension UInt256 {
    var asDecimalString: String {
        description
    }
}


