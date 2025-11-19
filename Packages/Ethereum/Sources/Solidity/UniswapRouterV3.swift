//
//  UniswapRouterV3.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

public enum UniswapRouterV3 {
    public struct exactInputSingle: SolContractFunction, SolKeyPathTuple {
        public var params: ExactInputSingleParams

        public static var keyPaths: [AnyKeyPath] = [\Self.params]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amountOut: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.amountOut]

            public init(amountOut: Sol.UInt256) {
                self.amountOut = amountOut
            }

            public init() {
                self.init(amountOut: .init())
            }
        }

        public typealias Returns = ReturnData

        public init(params: ExactInputSingleParams) {
            self.params = params
        }

        public init() {
            self.init(params: .init())
        }

        public struct ExactInputSingleParams: SolEncodableTuple, SolKeyPathTuple {
            public var tokenIn: Sol.Address
            public var tokenOut: Sol.Address
            public var fee: Sol.UInt24
            public var recipient: Sol.Address
            public var deadline: Sol.UInt256
            public var amountIn: Sol.UInt256
            public var amountOutMinimum: Sol.UInt256
            public var sqrtPriceLimitX96: Sol.UInt160

            public static var keyPaths: [AnyKeyPath] = [
                \Self.tokenIn,
                \Self.tokenOut,
                \Self.fee,
                \Self.recipient,
                \Self.deadline,
                \Self.amountIn,
                \Self.amountOutMinimum,
                \Self.sqrtPriceLimitX96
            ]

            public init(tokenIn: Sol.Address,
                        tokenOut: Sol.Address,
                        fee: Sol.UInt24,
                        recipient: Sol.Address,
                        deadline: Sol.UInt256,
                        amountIn: Sol.UInt256,
                        amountOutMinimum: Sol.UInt256,
                        sqrtPriceLimitX96: Sol.UInt160) {
                self.tokenIn = tokenIn
                self.tokenOut = tokenOut
                self.fee = fee
                self.recipient = recipient
                self.deadline = deadline
                self.amountIn = amountIn
                self.amountOutMinimum = amountOutMinimum
                self.sqrtPriceLimitX96 = sqrtPriceLimitX96
            }

            public init() {
                self.init(tokenIn: .init(),
                          tokenOut: .init(),
                          fee: .init(),
                          recipient: .init(),
                          deadline: .init(),
                          amountIn: .init(),
                          amountOutMinimum: .init(),
                          sqrtPriceLimitX96: .init())
            }
        }
    }

    public struct exactInput: SolContractFunction, SolKeyPathTuple {
        public var params: ExactInputParams

        public static var keyPaths: [AnyKeyPath] = [\Self.params]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amountOut: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.amountOut]

            public init(amountOut: Sol.UInt256) {
                self.amountOut = amountOut
            }

            public init() {
                self.init(amountOut: .init())
            }
        }

        public typealias Returns = ReturnData

        public init(params: ExactInputParams) {
            self.params = params
        }

        public init() {
            self.init(params: .init())
        }

        public struct ExactInputParams: SolEncodableTuple, SolKeyPathTuple {
            public var path: Sol.Bytes
            public var recipient: Sol.Address
            public var deadline: Sol.UInt256
            public var amountIn: Sol.UInt256
            public var amountOutMinimum: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [
                \Self.path,
                \Self.recipient,
                \Self.deadline,
                \Self.amountIn,
                \Self.amountOutMinimum
            ]

            public init(path: Sol.Bytes,
                        recipient: Sol.Address,
                        deadline: Sol.UInt256,
                        amountIn: Sol.UInt256,
                        amountOutMinimum: Sol.UInt256) {
                self.path = path
                self.recipient = recipient
                self.deadline = deadline
                self.amountIn = amountIn
                self.amountOutMinimum = amountOutMinimum
            }

            public init() {
                self.init(path: .init(),
                          recipient: .init(),
                          deadline: .init(),
                          amountIn: .init(),
                          amountOutMinimum: .init())
            }
        }
    }

    public struct exactOutputSingle: SolContractFunction, SolKeyPathTuple {
        public var params: ExactOutputSingleParams

        public static var keyPaths: [AnyKeyPath] = [\Self.params]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amountIn: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.amountIn]

            public init(amountIn: Sol.UInt256) {
                self.amountIn = amountIn
            }

            public init() {
                self.init(amountIn: .init())
            }
        }

        public typealias Returns = ReturnData

        public init(params: ExactOutputSingleParams) {
            self.params = params
        }

        public init() {
            self.init(params: .init())
        }

        public struct ExactOutputSingleParams: SolEncodableTuple, SolKeyPathTuple {
            public var tokenIn: Sol.Address
            public var tokenOut: Sol.Address
            public var fee: Sol.UInt24
            public var recipient: Sol.Address
            public var deadline: Sol.UInt256
            public var amountOut: Sol.UInt256
            public var amountInMaximum: Sol.UInt256
            public var sqrtPriceLimitX96: Sol.UInt160

            public static var keyPaths: [AnyKeyPath] = [
                \Self.tokenIn,
                \Self.tokenOut,
                \Self.fee,
                \Self.recipient,
                \Self.deadline,
                \Self.amountOut,
                \Self.amountInMaximum,
                \Self.sqrtPriceLimitX96
            ]

            public init(tokenIn: Sol.Address,
                        tokenOut: Sol.Address,
                        fee: Sol.UInt24,
                        recipient: Sol.Address,
                        deadline: Sol.UInt256,
                        amountOut: Sol.UInt256,
                        amountInMaximum: Sol.UInt256,
                        sqrtPriceLimitX96: Sol.UInt160) {
                self.tokenIn = tokenIn
                self.tokenOut = tokenOut
                self.fee = fee
                self.recipient = recipient
                self.deadline = deadline
                self.amountOut = amountOut
                self.amountInMaximum = amountInMaximum
                self.sqrtPriceLimitX96 = sqrtPriceLimitX96
            }

            public init() {
                self.init(tokenIn: .init(),
                          tokenOut: .init(),
                          fee: .init(),
                          recipient: .init(),
                          deadline: .init(),
                          amountOut: .init(),
                          amountInMaximum: .init(),
                          sqrtPriceLimitX96: .init())
            }
        }
    }

    public struct exactOutput: SolContractFunction, SolKeyPathTuple {
        public var params: ExactOutputParams

        public static var keyPaths: [AnyKeyPath] = [\Self.params]

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amountIn: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [\Self.amountIn]

            public init(amountIn: Sol.UInt256) {
                self.amountIn = amountIn
            }

            public init() {
                self.init(amountIn: .init())
            }
        }

        public typealias Returns = ReturnData

        public init(params: ExactOutputParams) {
            self.params = params
        }

        public init() {
            self.init(params: .init())
        }

        public struct ExactOutputParams: SolEncodableTuple, SolKeyPathTuple {
            public var path: Sol.Bytes
            public var recipient: Sol.Address
            public var deadline: Sol.UInt256
            public var amountOut: Sol.UInt256
            public var amountInMaximum: Sol.UInt256

            public static var keyPaths: [AnyKeyPath] = [
                \Self.path,
                \Self.recipient,
                \Self.deadline,
                \Self.amountOut,
                \Self.amountInMaximum
            ]

            public init(path: Sol.Bytes,
                        recipient: Sol.Address,
                        deadline: Sol.UInt256,
                        amountOut: Sol.UInt256,
                        amountInMaximum: Sol.UInt256) {
                self.path = path
                self.recipient = recipient
                self.deadline = deadline
                self.amountOut = amountOut
                self.amountInMaximum = amountInMaximum
            }

            public init() {
                self.init(path: .init(),
                          recipient: .init(),
                          deadline: .init(),
                          amountOut: .init(),
                          amountInMaximum: .init())
            }
        }
    }
}

