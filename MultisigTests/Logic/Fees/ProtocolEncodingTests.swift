//
//  ProtocolEncodingTests.swift
//  MultisigTests
//
//  Created by GPT-5 Codex on 15.11.25.
//

import XCTest
import Solidity
@testable import Multisig

final class ProtocolEncodingTests: XCTestCase {
    func testAaveSupplySelector() {
        let call = AavePool.supply(asset: Sol.Address(0x1),
                                   amount: Sol.UInt256(1),
                                   onBehalfOf: Sol.Address(0x2),
                                   referralCode: Sol.UInt16(0))
        let selector = Data(call.encode().prefix(4)).toHexStringWithPrefix()
        XCTAssertEqual(selector, "0x617ba037")
    }

    func testUniswapV2SwapExactTokensForTokensSelector() {
        let path = Sol.Array(elements: [Sol.Address(0x1), Sol.Address(0x2)])
        let call = UniswapRouterV2.swapExactTokensForTokens(amountIn: Sol.UInt256(1),
                                                            amountOutMin: Sol.UInt256(0),
                                                            path: path,
                                                            to: Sol.Address(0x3),
                                                            deadline: Sol.UInt256(0))
        let selector = Data(call.encode().prefix(4)).toHexStringWithPrefix()
        XCTAssertEqual(selector, "0x38ed1739")
    }

    func testUniswapV3ExactInputSingleSelector() {
        var params = UniswapRouterV3.exactInputSingle.ExactInputSingleParams()
        params.tokenIn = Sol.Address(0x1)
        params.tokenOut = Sol.Address(0x2)
        params.fee = Sol.UInt24(0)
        params.recipient = Sol.Address(0x3)
        params.deadline = Sol.UInt256(0)
        params.amountIn = Sol.UInt256(1)
        params.amountOutMinimum = Sol.UInt256(0)
        params.sqrtPriceLimitX96 = Sol.UInt160(0)
        let call = UniswapRouterV3.exactInputSingle(params: params)
        let selector = Data(call.encode().prefix(4)).toHexStringWithPrefix()
        XCTAssertEqual(selector, "0x414bf389")
    }

    func testFunctionSelectorCatalogLoadsERC20Transfer() {
        let selector = Data(ethHex: "0xa9059cbb")
        let catalog = makeCatalog()
        let entry = catalog.entry(for: selector)
        XCTAssertEqual(entry?.functionSignature, "transfer(address,uint256)")
    }

    private func makeCatalog() -> FunctionSelectorCatalog {
        let testFileURL = URL(fileURLWithPath: #file)
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Fees
            .deletingLastPathComponent() // Logic
            .deletingLastPathComponent() // MultisigTests
            .deletingLastPathComponent() // project root
        let jsonURL = projectRoot
            .appendingPathComponent("Multisig")
            .appendingPathComponent("Logic")
            .appendingPathComponent("function-selectors.json")
        return FunctionSelectorCatalog(jsonURL: jsonURL) ?? FunctionSelectorCatalog()
    }
}

