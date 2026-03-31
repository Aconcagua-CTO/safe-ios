//
//  TransactionBatchBuilder.swift
//  Multisig
//
//  Created by GPT-5 Codex on 15.11.25.
//

import Foundation
import BigInt
import Solidity
import SafeDeployments
import SafeAbi

final class TransactionBatchBuilder {
    struct Result {
        let transaction: Transaction
        let intent: Intent
        let originalAmount: UInt256
        let feeAmount: UInt256
        let netAmount: UInt256
        let treasury: Address
        let basisPoints: Int
        let multiSendAddress: Address
        let legs: [Leg]
    }

    struct Leg {
        let name: String
        let operation: SCGModels.Operation
        let to: Address
        let value: UInt256
        let data: Data
    }

    struct FeeConfiguration {
        let basisPoints: UInt256
        let treasury: Address
        let rawBasisPoints: Int

        static func load() -> FeeConfiguration? {
            let bpsValue = App.configuration.services.feeBasisPoints
            guard bpsValue > 0 else {
                TransactionFeeLogger.info("Fee configuration disabled (basis points = \(bpsValue)).")
                return nil
            }
            let treasuryString = App.configuration.services.feeTreasuryAddress
            guard let treasuryAddress = Address(treasuryString), !treasuryAddress.isZero else {
                TransactionFeeLogger.warning("Invalid fee treasury address \(treasuryString).")
                return nil
            }
            return FeeConfiguration(basisPoints: UInt256(bpsValue), treasury: treasuryAddress, rawBasisPoints: bpsValue)
        }
    }

    enum SwapProtocol {
        case uniswapV2
        case pancakeSwapV2
        case uniswapV3
    }

    enum Intent {
        case erc20Transfer(token: Address, recipient: Address, amount: UInt256)
        case aaveSupply(pool: Address, asset: Address, amount: UInt256, onBehalfOf: Sol.Address, referralCode: Sol.UInt16)
        case aaveDeposit(pool: Address, asset: Address, amount: UInt256, onBehalfOf: Sol.Address, referralCode: Sol.UInt16)
        case swapExactTokensForTokens(router: Address,
                                      amountIn: UInt256,
                                      amountOutMin: UInt256,
                                      path: [Address],
                                      recipient: Address,
                                      deadline: UInt256,
                                      protocolType: SwapProtocol)
        case swapExactTokensForETH(router: Address,
                                   amountIn: UInt256,
                                   amountOutMin: UInt256,
                                   path: [Address],
                                   recipient: Address,
                                   deadline: UInt256,
                                   protocolType: SwapProtocol)
        case swapExactETHForTokens(router: Address,
                                   amountOutMin: UInt256,
                                   path: [Address],
                                   recipient: Address,
                                   deadline: UInt256,
                                   protocolType: SwapProtocol,
                                   ethValue: UInt256)
        case swapExactInputSingleV3(router: Address,
                                    params: UniswapRouterV3.exactInputSingle.ExactInputSingleParams)
        case swapExactInputV3(router: Address,
                               params: UniswapRouterV3.exactInput.ExactInputParams)
        case cowSwapSetPreSignature(settlement: Address,
                                     sellToken: Address,
                                     buyToken: Address,
                                     sellAmount: UInt256,
                                     buyAmount: UInt256,
                                     order: CowSwapSettlement.setPreSignature.Order)
        case stargateSwap(router: Address,
                          dstChainId: UInt16,
                          srcPoolId: UInt256,
                          dstPoolId: UInt256,
                          refundAddress: Address,
                          amountLD: UInt256,
                          minAmountLD: UInt256,
                          payload: Data)
    }

    private let transaction: Transaction
    private let safe: Safe
    private let config: FeeConfiguration
    private let catalog: FunctionSelectorCatalog
    private let availableBalance: UInt256?

    private init(transaction: Transaction,
                 safe: Safe,
                 config: FeeConfiguration,
                 catalog: FunctionSelectorCatalog,
                 availableBalance: UInt256?) {
        self.transaction = transaction
        self.safe = safe
        self.config = config
        self.catalog = catalog
        self.availableBalance = availableBalance
    }

    static func build(transaction: Transaction, safe: Safe, availableBalance: UInt256? = nil) -> Result? {
        guard let config = FeeConfiguration.load() else { return nil }
        let catalog = FunctionSelectorCatalog.shared
        let builder = TransactionBatchBuilder(transaction: transaction,
                                              safe: safe,
                                              config: config,
                                              catalog: catalog,
                                              availableBalance: availableBalance)
        return builder.build()
    }

    private func build() -> Result? {
        guard let chainId = safe.chain?.id else {
            TransactionFeeLogger.warning("Safe missing chain id – cannot compute fee transaction.")
            return nil
        }

        guard let data = transaction.data?.data, data.count >= 4 else {
            TransactionFeeLogger.info("Transaction has no calldata selector – skipping fee batching.")
            return nil
        }
        let selectorLength = Swift.min(4, data.count)
        let selector = data.subdata(in: 0..<selectorLength)

        guard let entry = catalog.entry(for: selector) else {
            TransactionFeeLogger.debug("No catalog entry for selector \(selector.toHexStringWithPrefix()) – skipping.")
            return nil
        }

        guard catalog.isExpectedContract(entry,
                                          transactionAddress: transaction.to,
                                          chainId: chainId) else {
            TransactionFeeLogger.warning("Selector \(entry.functionSignature) does not match expected contract for chain \(chainId). Transaction to \(transaction.to.address.checksummed).")
            return nil
        }

        guard let intent = classify(entry: entry, data: data) else {
            TransactionFeeLogger.debug("Unsupported transaction \(entry.functionSignature) – skipping fee batching.")
            return nil
        }

        TransactionFeeLogger.info("Preparing fee batch for \(entry.protocolName) \(entry.functionName) on chain \(chainId).")

        guard let computation = compute(intent: intent) else {
            TransactionFeeLogger.warning("Failed to compute fee legs for \(entry.functionSignature).")
            return nil
        }

        guard let assembled = assembleTransaction(legs: computation.legs,
                                                  chainId: chainId) else {
            TransactionFeeLogger.error("Failed to assemble multisend transaction.")
            return nil
        }
        let metaTransaction = assembled.transaction
        let multiSendAddress = assembled.multiSend

        TransactionFeeLogger.info("Constructed fee batch with \(computation.legs.count) legs. Original amount=\(computation.originalAmount.asDecimalString), net=\(computation.netAmount.asDecimalString), fee=\(computation.feeAmount.asDecimalString).")

        logLegs(computation.legs)

        return Result(transaction: metaTransaction,
                      intent: intent,
                      originalAmount: computation.originalAmount,
                      feeAmount: computation.feeAmount,
                      netAmount: computation.netAmount,
                      treasury: config.treasury,
                      basisPoints: config.rawBasisPoints,
                      multiSendAddress: multiSendAddress,
                      legs: computation.legs)
    }

    private func classify(entry: FunctionSelectorCatalog.Entry, data: Data) -> Intent? {
        switch entry.functionSignature {
        case "transfer(address,uint256)":
            return classifyERC20Transfer(data: data)
        case "supply(address,uint256,address,uint16)":
            return classifyAaveSupply(data: data)
        case "deposit(address,uint256,address,uint16)":
            return classifyAaveDeposit(data: data)
        case "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)":
            return classifySwapExactTokensForTokens(data: data, protocolName: entry.protocolName)
        case "swapExactTokensForETH(uint256,uint256,address[],address,uint256)":
            return classifySwapExactTokensForETH(data: data, protocolName: entry.protocolName)
        case "swapExactETHForTokens(uint256,address[],address,uint256)":
            return classifySwapExactETHForTokens(data: data, protocolName: entry.protocolName)
        case "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))":
            return classifyV3ExactInputSingle(data: data)
        case "exactInput((bytes,address,uint256,uint256,uint256))":
            return classifyV3ExactInput(data: data)
        case "setPreSignature((address,address,address,uint256,uint256,bytes32,uint256,bytes32,bytes32,uint32,bool,bytes32),bool)":
            return classifyCowSwapSetPreSignature(data: data)
        case "invalidateOrder((address,address,address,uint256,uint256,bytes32,uint256,bytes32,bytes32,uint32,bool,bytes32))":
            // invalidateOrder doesn't require approval, skip fee batching
            return nil
        case "swap(uint16,uint256,uint256,address,uint256,uint256,bytes)":
            return classifyStargateSwap(data: data)
        default:
            TransactionFeeLogger.debug("Selector \(entry.functionSignature) currently unsupported for fee batching.")
            return nil
        }
    }

    private func classifyERC20Transfer(data: Data) -> Intent? {
        var call = ERC20.transfer()
        var offset = 0
        if (try? call.decode(from: data, offset: &offset)) != nil {
            let amount = UInt256(sol: call.value)
            let recipient = Address(call.to)
            let token = transaction.to.address
            TransactionFeeLogger.debug("Decoded ERC20 transfer: token=\(token.checksummed), recipient=\(recipient.checksummed), amount=\(amount.asDecimalString)")
            return .erc20Transfer(token: token, recipient: recipient, amount: amount)
        } else {
            guard
                let amount = readUInt256(data: data, range: 36..<68),
                let recipient = readAddress(data: data, range: 4..<36)
            else {
                TransactionFeeLogger.warning("Failed to decode ERC20.transfer calldata.")
                return nil
            }
            return .erc20Transfer(token: transaction.to.address,
                                  recipient: recipient,
                                  amount: amount)
        }
    }

    private func classifyAaveSupply(data: Data) -> Intent? {
        var call = AavePool.supply()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode Aave V3 supply calldata.")
            return nil
        }
        let amount = UInt256(sol: call.amount)
        let asset = Address(call.asset)
        let pool = transaction.to.address
        TransactionFeeLogger.debug("Decoded Aave supply: pool=\(pool.checksummed), asset=\(asset.checksummed), amount=\(amount.asDecimalString)")
        return .aaveSupply(pool: pool,
                           asset: asset,
                           amount: amount,
                           onBehalfOf: call.onBehalfOf,
                           referralCode: call.referralCode)
    }

    private func classifyAaveDeposit(data: Data) -> Intent? {
        var call = AavePool.deposit()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode Aave V2 deposit calldata.")
            return nil
        }
        let amount = UInt256(sol: call.amount)
        let asset = Address(call.asset)
        let pool = transaction.to.address
        TransactionFeeLogger.debug("Decoded Aave deposit: pool=\(pool.checksummed), asset=\(asset.checksummed), amount=\(amount.asDecimalString)")
        return .aaveDeposit(pool: pool,
                            asset: asset,
                            amount: amount,
                            onBehalfOf: call.onBehalfOf,
                            referralCode: call.referralCode)
    }

    private func classifySwapExactTokensForTokens(data: Data, protocolName: String) -> Intent? {
        var call = UniswapRouterV2.swapExactTokensForTokens()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode swapExactTokensForTokens calldata.")
            return nil
        }
        let amountIn = UInt256(sol: call.amountIn)
        let amountOutMin = UInt256(sol: call.amountOutMin)
        let path = call.path.elements.map(Address.init)
        let recipient = Address(call.to)
        let deadline = UInt256(sol: call.deadline)
        let router = transaction.to.address
        let proto = protocolName.lowercased().contains("pancake") ? SwapProtocol.pancakeSwapV2 : .uniswapV2
        return .swapExactTokensForTokens(router: router,
                                         amountIn: amountIn,
                                         amountOutMin: amountOutMin,
                                         path: path,
                                         recipient: recipient,
                                         deadline: deadline,
                                         protocolType: proto)
    }

    private func classifySwapExactTokensForETH(data: Data, protocolName: String) -> Intent? {
        var call = UniswapRouterV2.swapExactTokensForETH()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode swapExactTokensForETH calldata.")
            return nil
        }
        let amountIn = UInt256(sol: call.amountIn)
        let amountOutMin = UInt256(sol: call.amountOutMin)
        let path = call.path.elements.map(Address.init)
        let recipient = Address(call.to)
        let deadline = UInt256(sol: call.deadline)
        let router = transaction.to.address
        let proto = protocolName.lowercased().contains("pancake") ? SwapProtocol.pancakeSwapV2 : .uniswapV2
        return .swapExactTokensForETH(router: router,
                                      amountIn: amountIn,
                                      amountOutMin: amountOutMin,
                                      path: path,
                                      recipient: recipient,
                                      deadline: deadline,
                                      protocolType: proto)
    }

    private func classifySwapExactETHForTokens(data: Data, protocolName: String) -> Intent? {
        var call = UniswapRouterV2.swapExactETHForTokens()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode swapExactETHForTokens calldata.")
            return nil
        }
        let amountOutMin = UInt256(sol: call.amountOutMin)
        let path = call.path.elements.map(Address.init)
        let recipient = Address(call.to)
        let deadline = UInt256(sol: call.deadline)
        let router = transaction.to.address
        let value = transaction.value.value
        let proto = protocolName.lowercased().contains("pancake") ? SwapProtocol.pancakeSwapV2 : .uniswapV2
        return .swapExactETHForTokens(router: router,
                                      amountOutMin: amountOutMin,
                                      path: path,
                                      recipient: recipient,
                                      deadline: deadline,
                                      protocolType: proto,
                                      ethValue: value)
    }

    private func classifyV3ExactInputSingle(data: Data) -> Intent? {
        var call = UniswapRouterV3.exactInputSingle()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode Uniswap V3 exactInputSingle calldata.")
            return nil
        }
        let router = transaction.to.address
        return .swapExactInputSingleV3(router: router, params: call.params)
    }

    private func classifyV3ExactInput(data: Data) -> Intent? {
        var call = UniswapRouterV3.exactInput()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode Uniswap V3 exactInput calldata.")
            return nil
        }
        let router = transaction.to.address
        return .swapExactInputV3(router: router, params: call.params)
    }

    private func classifyCowSwapSetPreSignature(data: Data) -> Intent? {
        var call = CowSwapSettlement.setPreSignature()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode CowSwap setPreSignature calldata.")
            return nil
        }
        let settlement = transaction.to.address
        let sellToken = Address(call.order.sellToken)
        let buyToken = Address(call.order.buyToken)
        let sellAmount = UInt256(sol: call.order.sellAmount)
        let buyAmount = UInt256(sol: call.order.buyAmount)
        TransactionFeeLogger.debug("Decoded CowSwap setPreSignature: settlement=\(settlement.checksummed), sellToken=\(sellToken.checksummed), buyToken=\(buyToken.checksummed), sellAmount=\(sellAmount.asDecimalString), buyAmount=\(buyAmount.asDecimalString)")
        return .cowSwapSetPreSignature(settlement: settlement,
                                        sellToken: sellToken,
                                        buyToken: buyToken,
                                        sellAmount: sellAmount,
                                        buyAmount: buyAmount,
                                        order: call.order)
    }

    private func classifyStargateSwap(data: Data) -> Intent? {
        var call = StargateRouter.swap()
        var offset = 0
        guard (try? call.decode(from: data, offset: &offset)) != nil else {
            TransactionFeeLogger.warning("Failed to decode Stargate swap calldata.")
            return nil
        }
        let router = transaction.to.address
        let dstChainId = UInt16(call.dstChainId)
        let srcPoolId = UInt256(sol: call.srcPoolId)
        let dstPoolId = UInt256(sol: call.dstPoolId)
        let refundAddress = Address(call.refundAddress)
        let amountLD = UInt256(sol: call.amountLD)
        let minAmountLD = UInt256(sol: call.minAmountLD)
        let payload = call.payload.storage
        TransactionFeeLogger.debug("Decoded Stargate swap: router=\(router.checksummed), dstChainId=\(dstChainId), srcPoolId=\(srcPoolId.asDecimalString), dstPoolId=\(dstPoolId.asDecimalString), amountLD=\(amountLD.asDecimalString), minAmountLD=\(minAmountLD.asDecimalString)")
        return .stargateSwap(router: router,
                             dstChainId: dstChainId,
                             srcPoolId: srcPoolId,
                             dstPoolId: dstPoolId,
                             refundAddress: refundAddress,
                             amountLD: amountLD,
                             minAmountLD: minAmountLD,
                             payload: payload)
    }

    private struct Computation {
        let originalAmount: UInt256
        let netAmount: UInt256
        let feeAmount: UInt256
        let legs: [Leg]
    }

    private func compute(intent: Intent) -> Computation? {
        switch intent {
        case let .erc20Transfer(token, recipient, amount):
            return computeERC20Transfer(token: token, recipient: recipient, amount: amount)
        case let .aaveSupply(pool, asset, amount, onBehalfOf, referralCode):
            return computeAaveSupply(pool: pool, asset: asset, amount: amount, onBehalfOf: onBehalfOf, referralCode: referralCode)
        case let .aaveDeposit(pool, asset, amount, onBehalfOf, referralCode):
            return computeAaveDeposit(pool: pool, asset: asset, amount: amount, onBehalfOf: onBehalfOf, referralCode: referralCode)
        case let .swapExactTokensForTokens(router, amountIn, amountOutMin, path, recipient, deadline, proto):
            return computeSwapExactTokensForTokens(router: router, amountIn: amountIn, amountOutMin: amountOutMin, path: path, recipient: recipient, deadline: deadline, protocolType: proto)
        case let .swapExactTokensForETH(router, amountIn, amountOutMin, path, recipient, deadline, proto):
            return computeSwapExactTokensForETH(router: router, amountIn: amountIn, amountOutMin: amountOutMin, path: path, recipient: recipient, deadline: deadline, protocolType: proto)
        case let .swapExactETHForTokens(router, amountOutMin, path, recipient, deadline, proto, ethValue):
            return computeSwapExactETHForTokens(router: router, amountOutMin: amountOutMin, path: path, recipient: recipient, deadline: deadline, protocolType: proto, ethValue: ethValue)
        case let .swapExactInputSingleV3(router, params):
            return computeSwapExactInputSingleV3(router: router, params: params)
        case let .swapExactInputV3(router, params):
            return computeSwapExactInputV3(router: router, params: params)
        case let .cowSwapSetPreSignature(settlement, sellToken, buyToken, sellAmount, buyAmount, order):
            return computeCowSwapSetPreSignature(settlement: settlement, sellToken: sellToken, buyToken: buyToken, sellAmount: sellAmount, buyAmount: buyAmount, order: order)
        case let .stargateSwap(router, dstChainId, srcPoolId, dstPoolId, refundAddress, amountLD, minAmountLD, payload):
            return computeStargateSwap(router: router, dstChainId: dstChainId, srcPoolId: srcPoolId, dstPoolId: dstPoolId, refundAddress: refundAddress, amountLD: amountLD, minAmountLD: minAmountLD, payload: payload)
        }
    }

    private func computeERC20Transfer(token: Address, recipient: Address, amount: UInt256) -> Computation? {
        guard let feeAmount = calculateFee(for: amount) else {
            TransactionFeeLogger.info("ERC20 transfer amount too small for fee – skipping.")
            return nil
        }
        let shouldDeductFromAmount: Bool
        if let availableBalance = availableBalance {
            shouldDeductFromAmount = (amount + feeAmount) > availableBalance
        } else {
            shouldDeductFromAmount = true
        }

        let netAmount: UInt256
        if shouldDeductFromAmount {
            netAmount = amount - feeAmount
            guard netAmount > 0 else {
                TransactionFeeLogger.warning("ERC20 transfer net amount would be zero – skipping.")
                return nil
            }
        } else {
            netAmount = amount
        }

        let mainCall = ERC20.transfer(to: Sol.Address(stringLiteral: recipient.checksummedWithoutPrefix),
                                      value: Sol.UInt256(netAmount))
        let feeCall = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                     value: Sol.UInt256(feeAmount))

        let legs: [Leg] = [
            Leg(name: "ERC20 Transfer (net)",
                operation: .call,
                to: token,
                value: .zero,
                data: mainCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: token,
                value: .zero,
                data: feeCall.encode())
        ]

        return Computation(originalAmount: amount,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeAaveSupply(pool: Address,
                                   asset: Address,
                                   amount: UInt256,
                                   onBehalfOf: Sol.Address,
                                   referralCode: Sol.UInt16) -> Computation? {
        guard let feeAmount = calculateFee(for: amount) else {
            TransactionFeeLogger.info("Aave supply amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amount - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Aave supply net amount would be zero – skipping.")
            return nil
        }

        let approvalAmount = amount

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: pool.checksummedWithoutPrefix),
                                    value: Sol.UInt256(approvalAmount))
        let supply = AavePool.supply(asset: Sol.Address(stringLiteral: asset.checksummedWithoutPrefix),
                                     amount: Sol.UInt256(netAmount),
                                     onBehalfOf: onBehalfOf,
                                     referralCode: referralCode)
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: pool.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "Aave Approve",
                operation: .call,
                to: asset,
                value: .zero,
                data: approve.encode()),
            Leg(name: "Aave Supply (net)",
                operation: .call,
                to: pool,
                value: .zero,
                data: supply.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: asset,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "Aave Approval Reset",
                operation: .call,
                to: asset,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amount,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeAaveDeposit(pool: Address,
                                    asset: Address,
                                    amount: UInt256,
                                    onBehalfOf: Sol.Address,
                                    referralCode: Sol.UInt16) -> Computation? {
        guard let feeAmount = calculateFee(for: amount) else {
            TransactionFeeLogger.info("Aave deposit amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amount - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Aave deposit net amount would be zero – skipping.")
            return nil
        }

        let approvalAmount = amount

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: pool.checksummedWithoutPrefix),
                                    value: Sol.UInt256(approvalAmount))
        let deposit = AavePool.deposit(asset: Sol.Address(stringLiteral: asset.checksummedWithoutPrefix),
                                       amount: Sol.UInt256(netAmount),
                                       onBehalfOf: onBehalfOf,
                                       referralCode: referralCode)
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: pool.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "Aave Approve",
                operation: .call,
                to: asset,
                value: .zero,
                data: approve.encode()),
            Leg(name: "Aave Deposit (net)",
                operation: .call,
                to: pool,
                value: .zero,
                data: deposit.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: asset,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "Aave Approval Reset",
                operation: .call,
                to: asset,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amount,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeSwapExactTokensForTokens(router: Address,
                                                 amountIn: UInt256,
                                                 amountOutMin: UInt256,
                                                 path: [Address],
                                                 recipient: Address,
                                                 deadline: UInt256,
                                                 protocolType: SwapProtocol) -> Computation? {
        guard path.count >= 2 else {
            TransactionFeeLogger.warning("Swap path too short – skipping.")
            return nil
        }
        guard let feeAmount = calculateFee(for: amountIn) else {
            TransactionFeeLogger.info("Swap amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amountIn - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Swap net amount would be zero – skipping.")
            return nil
        }

        let adjustedOutMin = (amountOutMin * netAmount) / amountIn
        TransactionFeeLogger.debug("Adjusting amountOutMin from \(amountOutMin.asDecimalString) to \(adjustedOutMin.asDecimalString) for proportional slippage.")

        let inputToken = path.first!

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                    value: Sol.UInt256(amountIn))
        let pathArray = Sol.Array(elements: path.map { Sol.Address(stringLiteral: $0.checksummedWithoutPrefix) })
        let swapCall = UniswapRouterV2.swapExactTokensForTokens(amountIn: Sol.UInt256(netAmount),
                                                                amountOutMin: Sol.UInt256(adjustedOutMin),
                                                                path: pathArray,
                                                                to: Sol.Address(stringLiteral: recipient.checksummedWithoutPrefix),
                                                                deadline: Sol.UInt256(deadline))
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "\(protocolTypeLabel(protocolType)) Approve",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: approve.encode()),
            Leg(name: "\(protocolTypeLabel(protocolType)) Swap (net)",
                operation: .call,
                to: router,
                value: .zero,
                data: swapCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "\(protocolTypeLabel(protocolType)) Approval Reset",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amountIn,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeSwapExactTokensForETH(router: Address,
                                              amountIn: UInt256,
                                              amountOutMin: UInt256,
                                              path: [Address],
                                              recipient: Address,
                                              deadline: UInt256,
                                              protocolType: SwapProtocol) -> Computation? {
        guard path.count >= 2 else {
            TransactionFeeLogger.warning("Swap path too short – skipping.")
            return nil
        }
        guard let feeAmount = calculateFee(for: amountIn) else {
            TransactionFeeLogger.info("Swap amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amountIn - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Swap net amount would be zero – skipping.")
            return nil
        }

        let adjustedOutMin = (amountOutMin * netAmount) / amountIn

        let inputToken = path.first!

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                    value: Sol.UInt256(amountIn))
        let pathArray = Sol.Array(elements: path.map { Sol.Address(stringLiteral: $0.checksummedWithoutPrefix) })
        let swapCall = UniswapRouterV2.swapExactTokensForETH(amountIn: Sol.UInt256(netAmount),
                                                             amountOutMin: Sol.UInt256(adjustedOutMin),
                                                             path: pathArray,
                                                             to: Sol.Address(stringLiteral: recipient.checksummedWithoutPrefix),
                                                             deadline: Sol.UInt256(deadline))
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "\(protocolTypeLabel(protocolType)) Approve",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: approve.encode()),
            Leg(name: "\(protocolTypeLabel(protocolType)) Swap (net)",
                operation: .call,
                to: router,
                value: .zero,
                data: swapCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "\(protocolTypeLabel(protocolType)) Approval Reset",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amountIn,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeSwapExactETHForTokens(router: Address,
                                              amountOutMin: UInt256,
                                              path: [Address],
                                              recipient: Address,
                                              deadline: UInt256,
                                              protocolType: SwapProtocol,
                                              ethValue: UInt256) -> Computation? {
        guard path.count >= 2 else {
            TransactionFeeLogger.warning("Swap path too short – skipping.")
            return nil
        }
        guard let feeAmount = calculateFee(for: ethValue) else {
            TransactionFeeLogger.info("Swap ETH value too small for fee – skipping.")
            return nil
        }
        let netValue = ethValue - feeAmount
        guard netValue > 0 else {
            TransactionFeeLogger.warning("Swap net ETH amount would be zero – skipping.")
            return nil
        }

        let adjustedOutMin = (amountOutMin * netValue) / ethValue

        let pathArray = Sol.Array(elements: path.map { Sol.Address(stringLiteral: $0.checksummedWithoutPrefix) })
        let swapCall = UniswapRouterV2.swapExactETHForTokens(amountOutMin: Sol.UInt256(adjustedOutMin),
                                                             path: pathArray,
                                                             to: Sol.Address(stringLiteral: recipient.checksummedWithoutPrefix),
                                                             deadline: Sol.UInt256(deadline))

        let feeLeg = Leg(name: "Fee Transfer (ETH)",
                         operation: .call,
                         to: config.treasury,
                         value: feeAmount,
                         data: Data())

        let swapLeg = Leg(name: "\(protocolTypeLabel(protocolType)) Swap (net)",
                          operation: .call,
                          to: router,
                          value: netValue,
                          data: swapCall.encode())

        let legs = [swapLeg, feeLeg]

        return Computation(originalAmount: ethValue,
                           netAmount: netValue,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeSwapExactInputSingleV3(router: Address,
                                               params: UniswapRouterV3.exactInputSingle.ExactInputSingleParams) -> Computation? {
        let amountIn = UInt256(sol: params.amountIn)
        guard let feeAmount = calculateFee(for: amountIn) else {
            TransactionFeeLogger.info("Uniswap V3 amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amountIn - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Uniswap V3 net amount would be zero – skipping.")
            return nil
        }

        let adjustedAmountOutMinimum = (UInt256(sol: params.amountOutMinimum) * netAmount) / amountIn

        let inputToken = Address(params.tokenIn)

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                    value: Sol.UInt256(amountIn))
        var newParams = params
        newParams.amountIn = Sol.UInt256(netAmount)
        newParams.amountOutMinimum = Sol.UInt256(adjustedAmountOutMinimum)
        let swapCall = UniswapRouterV3.exactInputSingle(params: newParams)
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "Uniswap V3 Approve",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: approve.encode()),
            Leg(name: "Uniswap V3 Swap (net)",
                operation: .call,
                to: router,
                value: .zero,
                data: swapCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "Uniswap V3 Approval Reset",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amountIn,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeSwapExactInputV3(router: Address,
                                         params: UniswapRouterV3.exactInput.ExactInputParams) -> Computation? {
        let amountIn = UInt256(sol: params.amountIn)
        guard let feeAmount = calculateFee(for: amountIn) else {
            TransactionFeeLogger.info("Uniswap V3 amount too small for fee – skipping.")
            return nil
        }
        let netAmount = amountIn - feeAmount
        guard netAmount > 0 else {
            TransactionFeeLogger.warning("Uniswap V3 net amount would be zero – skipping.")
            return nil
        }

        let adjustedAmountOutMinimum = (UInt256(sol: params.amountOutMinimum) * netAmount) / amountIn

        guard let inputToken = decodeFirstToken(from: params.path.storage) else {
            TransactionFeeLogger.warning("Failed to decode first token from Uniswap V3 path.")
            return nil
        }

        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                    value: Sol.UInt256(amountIn))
        var newParams = params
        newParams.amountIn = Sol.UInt256(netAmount)
        newParams.amountOutMinimum = Sol.UInt256(adjustedAmountOutMinimum)
        let swapCall = UniswapRouterV3.exactInput(params: newParams)
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "Uniswap V3 Approve",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: approve.encode()),
            Leg(name: "Uniswap V3 Swap (net)",
                operation: .call,
                to: router,
                value: .zero,
                data: swapCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "Uniswap V3 Approval Reset",
                operation: .call,
                to: inputToken,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amountIn,
                           netAmount: netAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeCowSwapSetPreSignature(settlement: Address,
                                                sellToken: Address,
                                                buyToken: Address,
                                                sellAmount: UInt256,
                                                buyAmount: UInt256,
                                                order: CowSwapSettlement.setPreSignature.Order) -> Computation? {
        guard let feeAmount = calculateFee(for: sellAmount) else {
            TransactionFeeLogger.info("CowSwap sell amount too small for fee – skipping.")
            return nil
        }
        let netSellAmount = sellAmount - feeAmount
        guard netSellAmount > 0 else {
            TransactionFeeLogger.warning("CowSwap net sell amount would be zero – skipping.")
            return nil
        }

        // CowSwap requires approval of GPv2VaultRelayer
        // GPv2VaultRelayer addresses per chain
        // Ethereum: 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
        // Gnosis Chain: 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
        // In production, this should be looked up from chain-specific configuration
        let vaultRelayerAddress: Address
        if let chainId = safe.chain?.id {
            // GPv2VaultRelayer addresses per chain
            switch chainId {
            case "1": // Ethereum
                vaultRelayerAddress = (try? Address(from: "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110")) ?? settlement
            case "100": // Gnosis Chain
                vaultRelayerAddress = (try? Address(from: "0xC92E8bdf79f0507f65a392b0ab4667716BFE0110")) ?? settlement
            default:
                vaultRelayerAddress = settlement // Fallback
            }
        } else {
            vaultRelayerAddress = settlement
        }

        // Calculate approval amount: net amount + fee amount
        let approvalAmount = sellAmount

        // Create approval leg
        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: vaultRelayerAddress.checksummedWithoutPrefix),
                                    value: Sol.UInt256(approvalAmount))

        // Create modified order with net sell amount
        var modifiedOrder = order
        modifiedOrder.sellAmount = Sol.UInt256(netSellAmount)
        // Adjust buy amount proportionally if needed
        if sellAmount > 0 {
            let adjustedBuyAmount = (buyAmount * netSellAmount) / sellAmount
            modifiedOrder.buyAmount = Sol.UInt256(adjustedBuyAmount)
        }

        // Create setPreSignature call with modified order
        let setPreSignatureCall = CowSwapSettlement.setPreSignature(order: modifiedOrder, signed: Sol.Bool(true))

        // Create fee transfer leg
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))

        // Create approval reset leg (security: prevents over-approval)
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: vaultRelayerAddress.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "CowSwap Approve (GPv2VaultRelayer)",
                operation: .call,
                to: sellToken,
                value: .zero,
                data: approve.encode()),
            Leg(name: "CowSwap setPreSignature (net)",
                operation: .call,
                to: settlement,
                value: .zero,
                data: setPreSignatureCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: sellToken,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "CowSwap Approval Reset",
                operation: .call,
                to: sellToken,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: sellAmount,
                           netAmount: netSellAmount,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    private func computeStargateSwap(router: Address,
                                     dstChainId: UInt16,
                                     srcPoolId: UInt256,
                                     dstPoolId: UInt256,
                                     refundAddress: Address,
                                     amountLD: UInt256,
                                     minAmountLD: UInt256,
                                     payload: Data) -> Computation? {
        guard let feeAmount = calculateFee(for: amountLD) else {
            TransactionFeeLogger.info("Stargate swap amount too small for fee – skipping.")
            return nil
        }
        let netAmountLD = amountLD - feeAmount
        guard netAmountLD > 0 else {
            TransactionFeeLogger.warning("Stargate swap net amount would be zero – skipping.")
            return nil
        }

        // Determine token address for approval from pool ID
        // Stargate uses pool IDs to identify token pools
        // We need to map pool ID to token address for approval
        guard let tokenAddress = resolveTokenAddressFromPoolId(poolId: srcPoolId, chainId: safe.chain?.id ?? "1") else {
            TransactionFeeLogger.warning("Stargate swap detected but unable to resolve token address from pool ID \(srcPoolId.asDecimalString) on chain \(safe.chain?.id ?? "unknown"). Skipping fee batching.")
            return nil
        }

        // Calculate approval amount: exact amount needed
        let approvalAmount = amountLD

        // Create approval leg (approve Router contract)
        let approve = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                    value: Sol.UInt256(approvalAmount))

        // Adjust minAmountLD proportionally when reducing amountLD by fee
        let adjustedMinAmountLD = (minAmountLD * netAmountLD) / amountLD
        TransactionFeeLogger.debug("Adjusting minAmountLD from \(minAmountLD.asDecimalString) to \(adjustedMinAmountLD.asDecimalString) for proportional slippage.")

        // Create swap call with net amount
        let swapCall = StargateRouter.swap(dstChainId: Sol.UInt16(dstChainId),
                                            srcPoolId: Sol.UInt256(srcPoolId),
                                            dstPoolId: Sol.UInt256(dstPoolId),
                                            refundAddress: Sol.Address(stringLiteral: refundAddress.checksummedWithoutPrefix),
                                            amountLD: Sol.UInt256(netAmountLD),
                                            minAmountLD: Sol.UInt256(adjustedMinAmountLD),
                                            payload: Sol.Bytes(storage: payload))

        // Create fee transfer leg
        let feeTransfer = ERC20.transfer(to: Sol.Address(stringLiteral: config.treasury.checksummedWithoutPrefix),
                                         value: Sol.UInt256(feeAmount))

        // Create approval reset leg (security: prevents over-approval)
        let revoke = ERC20.approve(spender: Sol.Address(stringLiteral: router.checksummedWithoutPrefix),
                                   value: Sol.UInt256(UInt256.zero))

        let legs: [Leg] = [
            Leg(name: "Stargate Approve",
                operation: .call,
                to: tokenAddress,
                value: .zero,
                data: approve.encode()),
            Leg(name: "Stargate Swap (net)",
                operation: .call,
                to: router,
                value: .zero,
                data: swapCall.encode()),
            Leg(name: "Fee Transfer",
                operation: .call,
                to: tokenAddress,
                value: .zero,
                data: feeTransfer.encode()),
            Leg(name: "Stargate Approval Reset",
                operation: .call,
                to: tokenAddress,
                value: .zero,
                data: revoke.encode())
        ]

        return Computation(originalAmount: amountLD,
                           netAmount: netAmountLD,
                           feeAmount: feeAmount,
                           legs: legs)
    }

    /// Resolves token address from Stargate pool ID
    /// Pool IDs are chain-specific and map to token addresses
    /// Common pool IDs:
    /// - Pool 1: USDC
    /// - Pool 2: USDT
    /// - Pool 3: DAI
    /// - Pool 7: FRAX
    /// - Pool 13: ETH
    private func resolveTokenAddressFromPoolId(poolId: UInt256, chainId: String) -> Address? {
        // Stargate pool ID to token address mapping per chain
        // These are common pool IDs, but may vary by chain
        // NOTE: These addresses need verification from Stargate documentation
        let poolIdString = poolId.asDecimalString
        
        // Common pool IDs (may need adjustment per chain)
        // Pool 1 = USDC, Pool 2 = USDT, Pool 3 = DAI, Pool 7 = FRAX, Pool 13 = ETH
        switch chainId {
        case "1": // Ethereum Mainnet
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
            case "2": // USDT
                return try? Address(from: "0xdAC17F958D2ee523a2206206994597C13D831ec7")
            case "3": // DAI
                return try? Address(from: "0x6B175474E89094C44Da98b954EedeAC495271d0F")
            case "7": // FRAX
                return try? Address(from: "0x853d955aCEf822Db058eb8505911ED77F175b99e")
            case "13": // ETH
                return try? Address(from: "0x0000000000000000000000000000000000000000") // Native ETH, but Stargate uses WETH
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on Ethereum. Token address resolution failed.")
                return nil
            }
        case "137": // Polygon
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174")
            case "2": // USDT
                return try? Address(from: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F")
            case "3": // DAI
                return try? Address(from: "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063")
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on Polygon. Token address resolution failed.")
                return nil
            }
        case "42161": // Arbitrum
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8")
            case "2": // USDT
                return try? Address(from: "0xFd086BC7CD5C481DCC9C85ebE478A1C0b69FCbb9")
            case "3": // DAI
                return try? Address(from: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on Arbitrum. Token address resolution failed.")
                return nil
            }
        case "10": // Optimism
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0x7F5c764cB1414f8692694C65C5F8C0F5C3b85Cb")
            case "2": // USDT
                return try? Address(from: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58")
            case "3": // DAI
                return try? Address(from: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1")
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on Optimism. Token address resolution failed.")
                return nil
            }
        case "56": // BSC
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d")
            case "2": // USDT
                return try? Address(from: "0x55d398326f99059fF775485246999027B3197955")
            case "3": // BUSD
                return try? Address(from: "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56")
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on BSC. Token address resolution failed.")
                return nil
            }
        case "43114": // Avalanche
            switch poolIdString {
            case "1": // USDC
                return try? Address(from: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E")
            case "2": // USDT
                return try? Address(from: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7")
            default:
                TransactionFeeLogger.debug("Unknown Stargate pool ID \(poolIdString) on Avalanche. Token address resolution failed.")
                return nil
            }
        case "100": // Gnosis Chain
            // Stargate may not support Gnosis Chain, but include for completeness
            TransactionFeeLogger.debug("Stargate pool ID resolution on Gnosis Chain not yet implemented.")
            return nil
        default:
            TransactionFeeLogger.debug("Stargate pool ID resolution not implemented for chain \(chainId).")
            return nil
        }
    }

    private func assembleTransaction(legs: [Leg], chainId: String) -> (transaction: Transaction, multiSend: Address)? {
        guard !legs.isEmpty else {
            TransactionFeeLogger.warning("No legs produced for batching – skipping.")
            return nil
        }

        let encoded = encode(legs: legs)

        guard let deployment = try? SafeDeployments.Safe.Deployment.find(contract: .MultiSendCallOnly, version: .v1_4_1),
              let solAddress = deployment.address(for: chainId) else {
            TransactionFeeLogger.error("Unable to locate MultiSendCallOnly deployment for chain \(chainId).")
            return nil
        }

        let multiSendAddress = Address(solAddress)

        let contractVersion = safe.contractVersion ?? safe.semVer?.description ?? "1.3.0"
        let nonce = transaction.nonce

        guard let metaTransaction = Transaction(safeAddress: safe.addressValue,
                                                chainId: chainId,
                                                toAddress: multiSendAddress,
                                                contractVersion: contractVersion,
                                                amount: UInt256String(0),
                                                data: encoded,
                                                safeTxGas: transaction.safeTxGas,
                                                nonce: nonce,
                                                operation: .delegate,
                                                baseGas: transaction.baseGas,
                                                gasPrice: transaction.gasPrice,
                                                gasToken: transaction.gasToken.address,
                                                refundReceiver: transaction.refundReceiver.address) else {
            return nil
        }

        return (metaTransaction, multiSendAddress)
    }

    private func encode(legs: [Leg]) -> Data {
        let packed = legs.reduce(into: Data()) { partialResult, leg in
            partialResult.append(Sol.UInt8(leg.operation.rawValue).encodePacked())
            partialResult.append(Sol.Address(stringLiteral: leg.to.checksummedWithoutPrefix).encodePacked())
            partialResult.append(Sol.UInt256(leg.value).encodePacked())
            partialResult.append(Sol.UInt256(UInt256(leg.data.count)).encodePacked())
            partialResult.append(Sol.Bytes(storage: leg.data).encodePacked())
        }
        let transactions = Sol.Bytes(storage: packed)
        return MultiSendCallOnly_v1_3_0.multiSend(transactions: transactions).encode()
    }

    private func calculateFee(for amount: UInt256) -> UInt256? {
        guard amount > 0 else { return nil }
        let fee = (amount * config.basisPoints) / UInt256(10_000)
        return fee > 0 ? fee : nil
    }

    private func logLegs(_ legs: [Leg]) {
        for (index, leg) in legs.enumerated() {
            TransactionFeeLogger.debug("Leg \(index + 1): \(leg.name) -> to=\(leg.to.checksummed), op=\(leg.operation.name), value=\(leg.value.asDecimalString), dataSize=\(leg.data.count) bytes")
        }
    }

    private func protocolTypeLabel(_ proto: SwapProtocol) -> String {
        switch proto {
        case .uniswapV2:
            return "Uniswap V2"
        case .pancakeSwapV2:
            return "PancakeSwap V2"
        case .uniswapV3:
            return "Uniswap V3"
        }
    }

    private func decodeFirstToken(from path: Data) -> Address? {
        guard !path.isEmpty else { return nil }
        let length = Swift.min(20, path.count)
        let end = path.index(path.startIndex, offsetBy: length)
        let bytes = [UInt8](path[path.startIndex..<end])
        return address(from: Data(bytes))
    }

    private func readUInt256(data: Data, range: Range<Int>) -> UInt256? {
        guard data.count >= range.upperBound else { return nil }
        let subdata = data.subdata(in: range)
        var value = UInt256.zero
        for byte in subdata {
            value <<= 8
            value += UInt256(UInt(byte))
        }
        return value
    }

    private func readAddress(data: Data, range: Range<Int>) -> Address? {
        guard data.count >= range.upperBound else { return nil }
        let subdataBytes = [UInt8](data[range])
        let subdata = Data(subdataBytes)
        let clamped = Swift.min(20, subdata.count)
        let startIndex = subdata.index(subdata.endIndex, offsetBy: -clamped)
        let sliceBytes = [UInt8](subdata[startIndex..<subdata.endIndex])
        return address(from: Data(sliceBytes))
    }
}

private extension UInt256 {
    static let zero = UInt256(0)
}

private extension TransactionBatchBuilder {
    func address(from data: Data) -> Address? {
        guard !data.isEmpty else { return nil }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        return try? Address(from: "0x" + hex)
    }
}

