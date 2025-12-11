//
//  CowSwapSettlement.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

public enum CowSwapSettlement {
    public struct setPreSignature: SolContractFunction, SolKeyPathTuple {
        public var order: Order
        public var signed: Sol.Bool

        public static var keyPaths: [AnyKeyPath] = [
            \Self.order,
            \Self.signed
        ]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            // setPreSignature doesn't return a value
            public static var keyPaths: [AnyKeyPath] = []
            public init() {}
        }

        public typealias Returns = ReturnData

        public init(order: Order, signed: Sol.Bool) {
            self.order = order
            self.signed = signed
        }

        public init() {
            self.init(order: .init(), signed: .init())
        }

        public struct Order: SolEncodableTuple, SolKeyPathTuple {
            public var sellToken: Sol.Address
            public var buyToken: Sol.Address
            public var receiver: Sol.Address
            public var sellAmount: Sol.UInt256
            public var buyAmount: Sol.UInt256
            public var validTo: Sol.UInt32
            public var appData: Sol.Bytes32
            public var feeAmount: Sol.UInt256
            public var kind: Sol.Bytes32
            public var partiallyFillable: Sol.Bool
            public var sellTokenBalance: Sol.Bytes32
            public var buyTokenBalance: Sol.Bytes32

            public static var keyPaths: [AnyKeyPath] = [
                \Self.sellToken,
                \Self.buyToken,
                \Self.receiver,
                \Self.sellAmount,
                \Self.buyAmount,
                \Self.validTo,
                \Self.appData,
                \Self.feeAmount,
                \Self.kind,
                \Self.partiallyFillable,
                \Self.sellTokenBalance,
                \Self.buyTokenBalance
            ]

            public init(sellToken: Sol.Address,
                        buyToken: Sol.Address,
                        receiver: Sol.Address,
                        sellAmount: Sol.UInt256,
                        buyAmount: Sol.UInt256,
                        validTo: Sol.UInt32,
                        appData: Sol.Bytes32,
                        feeAmount: Sol.UInt256,
                        kind: Sol.Bytes32,
                        partiallyFillable: Sol.Bool,
                        sellTokenBalance: Sol.Bytes32,
                        buyTokenBalance: Sol.Bytes32) {
                self.sellToken = sellToken
                self.buyToken = buyToken
                self.receiver = receiver
                self.sellAmount = sellAmount
                self.buyAmount = buyAmount
                self.validTo = validTo
                self.appData = appData
                self.feeAmount = feeAmount
                self.kind = kind
                self.partiallyFillable = partiallyFillable
                self.sellTokenBalance = sellTokenBalance
                self.buyTokenBalance = buyTokenBalance
            }

            public init() {
                self.init(sellToken: .init(),
                          buyToken: .init(),
                          receiver: .init(),
                          sellAmount: .init(),
                          buyAmount: .init(),
                          validTo: .init(),
                          appData: .init(),
                          feeAmount: .init(),
                          kind: .init(),
                          partiallyFillable: .init(),
                          sellTokenBalance: .init(),
                          buyTokenBalance: .init())
            }
        }
    }

    public struct invalidateOrder: SolContractFunction, SolKeyPathTuple {
        public var order: setPreSignature.Order

        public static var keyPaths: [AnyKeyPath] = [\Self.order]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            // invalidateOrder doesn't return a value
            public static var keyPaths: [AnyKeyPath] = []
            public init() {}
        }

        public typealias Returns = ReturnData

        public init(order: setPreSignature.Order) {
            self.order = order
        }

        public init() {
            self.init(order: .init())
        }
    }
}

