//
//  AavePool.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

public enum AavePool {
    public struct supply: SolContractFunction, SolKeyPathTuple {
        public var asset: Sol.Address
        public var amount: Sol.UInt256
        public var onBehalfOf: Sol.Address
        public var referralCode: Sol.UInt16

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var value: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.value]

            public init(value: Sol.UInt256) {
                self.value = value
            }

            public init() {
                self.init(value: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.asset,
            \Self.amount,
            \Self.onBehalfOf,
            \Self.referralCode
        ]

        public init(asset: Sol.Address, amount: Sol.UInt256, onBehalfOf: Sol.Address, referralCode: Sol.UInt16) {
            self.asset = asset
            self.amount = amount
            self.onBehalfOf = onBehalfOf
            self.referralCode = referralCode
        }

        public init() {
            self.init(asset: .init(), amount: .init(), onBehalfOf: .init(), referralCode: .init())
        }
    }

    public struct deposit: SolContractFunction, SolKeyPathTuple {
        public var asset: Sol.Address
        public var amount: Sol.UInt256
        public var onBehalfOf: Sol.Address
        public var referralCode: Sol.UInt16

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var value: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.value]

            public init(value: Sol.UInt256) {
                self.value = value
            }

            public init() {
                self.init(value: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.asset,
            \Self.amount,
            \Self.onBehalfOf,
            \Self.referralCode
        ]

        public init(asset: Sol.Address, amount: Sol.UInt256, onBehalfOf: Sol.Address, referralCode: Sol.UInt16) {
            self.asset = asset
            self.amount = amount
            self.onBehalfOf = onBehalfOf
            self.referralCode = referralCode
        }

        public init() {
            self.init(asset: .init(), amount: .init(), onBehalfOf: .init(), referralCode: .init())
        }
    }
}

