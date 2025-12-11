//
//  StargateRouter.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

public enum StargateRouter {
    public struct swap: SolContractFunction, SolKeyPathTuple {
        public var dstChainId: Sol.UInt16
        public var srcPoolId: Sol.UInt256
        public var dstPoolId: Sol.UInt256
        public var refundAddress: Sol.Address
        public var amountLD: Sol.UInt256
        public var minAmountLD: Sol.UInt256
        public var payload: Sol.Bytes

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amountLD: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.amountLD]

            public init(amountLD: Sol.UInt256) {
                self.amountLD = amountLD
            }

            public init() {
                self.init(amountLD: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.dstChainId,
            \Self.srcPoolId,
            \Self.dstPoolId,
            \Self.refundAddress,
            \Self.amountLD,
            \Self.minAmountLD,
            \Self.payload
        ]

        public init(dstChainId: Sol.UInt16,
                    srcPoolId: Sol.UInt256,
                    dstPoolId: Sol.UInt256,
                    refundAddress: Sol.Address,
                    amountLD: Sol.UInt256,
                    minAmountLD: Sol.UInt256,
                    payload: Sol.Bytes) {
            self.dstChainId = dstChainId
            self.srcPoolId = srcPoolId
            self.dstPoolId = dstPoolId
            self.refundAddress = refundAddress
            self.amountLD = amountLD
            self.minAmountLD = minAmountLD
            self.payload = payload
        }

        public init() {
            self.init(dstChainId: .init(),
                      srcPoolId: .init(),
                      dstPoolId: .init(),
                      refundAddress: .init(),
                      amountLD: .init(),
                      minAmountLD: .init(),
                      payload: .init())
        }
    }
}

