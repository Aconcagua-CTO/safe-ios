//
//  UniswapRouterV2.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation

public enum UniswapRouterV2 {
    public struct swapExactTokensForTokens: SolContractFunction, SolKeyPathTuple {
        public var amountIn: Sol.UInt256
        public var amountOutMin: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountIn,
            \Self.amountOutMin,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountIn: Sol.UInt256,
                    amountOutMin: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountIn = amountIn
            self.amountOutMin = amountOutMin
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountIn: .init(),
                      amountOutMin: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }

    public struct swapTokensForExactTokens: SolContractFunction, SolKeyPathTuple {
        public var amountOut: Sol.UInt256
        public var amountInMax: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountOut,
            \Self.amountInMax,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountOut: Sol.UInt256,
                    amountInMax: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountOut = amountOut
            self.amountInMax = amountInMax
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountOut: .init(),
                      amountInMax: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }

    public struct swapExactETHForTokens: SolContractFunction, SolKeyPathTuple {
        public var amountOutMin: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountOutMin,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountOutMin: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountOutMin = amountOutMin
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountOutMin: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }

    public struct swapTokensForExactETH: SolContractFunction, SolKeyPathTuple {
        public var amountOut: Sol.UInt256
        public var amountInMax: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountOut,
            \Self.amountInMax,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountOut: Sol.UInt256,
                    amountInMax: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountOut = amountOut
            self.amountInMax = amountInMax
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountOut: .init(),
                      amountInMax: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }

    public struct swapExactTokensForETH: SolContractFunction, SolKeyPathTuple {
        public var amountIn: Sol.UInt256
        public var amountOutMin: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountIn,
            \Self.amountOutMin,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountIn: Sol.UInt256,
                    amountOutMin: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountIn = amountIn
            self.amountOutMin = amountOutMin
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountIn: .init(),
                      amountOutMin: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }

    public struct swapETHForExactTokens: SolContractFunction, SolKeyPathTuple {
        public var amountOut: Sol.UInt256
        public var path: Sol.Array<Sol.Address>
        public var to: Sol.Address
        public var deadline: Sol.UInt256

        public struct ReturnData: SolEncodableTuple, SolKeyPathTuple {
            public var amounts: Sol.Array<Sol.UInt256>

            public static var keyPaths: [AnyKeyPath] = [\Self.amounts]

            public init(amounts: Sol.Array<Sol.UInt256>) {
                self.amounts = amounts
            }

            public init() {
                self.init(amounts: .init())
            }
        }

        public typealias Returns = ReturnData

        public static var keyPaths: [AnyKeyPath] = [
            \Self.amountOut,
            \Self.path,
            \Self.to,
            \Self.deadline
        ]

        public init(amountOut: Sol.UInt256,
                    path: Sol.Array<Sol.Address>,
                    to: Sol.Address,
                    deadline: Sol.UInt256) {
            self.amountOut = amountOut
            self.path = path
            self.to = to
            self.deadline = deadline
        }

        public init() {
            self.init(amountOut: .init(),
                      path: .init(),
                      to: .init(),
                      deadline: .init())
        }
    }
}

