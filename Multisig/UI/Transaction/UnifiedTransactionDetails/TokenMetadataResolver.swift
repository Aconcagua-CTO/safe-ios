//
//  TokenMetadataResolver.swift
//  Multisig
//
//  Created by GPT-5 Codex on 2026-01-25.
//

import Foundation
import SwiftCryptoTokenFormatter

// #region agent log
#if DEBUG
private func tokenResolverAgentLog(location: String, message: String, hypothesisId: String, data: [String: Any]) {
    let payload: [String: Any] = [
        "sessionId": "f9c73e",
        "location": location,
        "message": message,
        "hypothesisId": hypothesisId,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard JSONSerialization.isValidJSONObject(payload),
          let body = try? JSONSerialization.data(withJSONObject: payload)
    else { return }
    let url = URL(string: "http://127.0.0.1:7242/ingest/d4162b9c-1479-4960-b98b-c3af51f135e6")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("f9c73e", forHTTPHeaderField: "X-Debug-Session-Id")
    req.httpBody = body
    req.timeoutInterval = 1
    URLSession.shared.dataTask(with: req).resume()
}
#endif
// #endregion agent log

final class TokenMetadataResolver {

    struct TokenMetadata {
        let symbol: String?
        let decimals: Int?
    }

    static let shared = TokenMetadataResolver()

    private let queue = DispatchQueue(label: "io.gnosis.multisig.tokenMetadataResolver", qos: .userInitiated)
    private var cache: [String: TokenMetadata] = [:]
    private var inFlight: [String: [(TokenMetadata) -> Void]] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTokenWhitelistUpdated),
            name: .tokenWhitelistUpdated,
            object: nil
        )
    }

    @objc private func handleTokenWhitelistUpdated() {
        invalidateCache()
    }

    func invalidateCache() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cache.removeAll()
            self.inFlight.removeAll()
        }
    }

    func resolve(token: Address, chain: Chain, completion: @escaping (TokenMetadata) -> Void) {
        let key = cacheKey(token: token, chainId: chain.id)
        if let cached = cache[key] {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            if let cached = self.cache[key] {
                DispatchQueue.main.async { completion(cached) }
                return
            }

            if self.inFlight[key] != nil {
                self.inFlight[key]?.append(completion)
                return
            }
            self.inFlight[key] = [completion]

            let metadata = self.fetchMetadata(token: token, chain: chain)
            self.cache[key] = metadata

            let completions = self.inFlight[key] ?? []
            self.inFlight[key] = nil
            DispatchQueue.main.async {
                completions.forEach { $0(metadata) }
            }
        }
    }

    func resolveSynchronously(token: Address, chain: Chain) -> TokenMetadata? {
        let key = cacheKey(token: token, chainId: chain.id)
        if let cached = cache[key] {
            return cached
        }
        let metadata = fetchMetadata(token: token, chain: chain)
        cache[key] = metadata
        if metadata.symbol == nil && metadata.decimals == nil {
            return nil
        }
        return metadata
    }

    private func cacheKey(token: Address, chainId: String?) -> String {
        let chainKey = chainId ?? "unknown"
        return "\(chainKey):\(token.checksummed.lowercased())"
    }

    private func fetchMetadata(token: Address, chain: Chain) -> TokenMetadata {
        var whitelistSymbol: String?
        var whitelistDecimals: Int?

        if let chainId = chain.id {
            let readWhitelist = {
                let addressString = token.checksummed
                if let entry = TokenWhitelist.by(chainId: chainId, networkAddress: addressString) {
                    whitelistSymbol = entry.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Note: `0` is a valid ERC-20 decimals value for some tokens.
                    whitelistDecimals = Int(entry.decimals)
                }
            }
            if Thread.isMainThread {
                readWhitelist()
            } else {
                DispatchQueue.main.sync(execute: readWhitelist)
            }
        }
        
        // Fallback: when whitelist metadata is missing/stale, use the latest balances cache.
        // This avoids rendering raw units (e.g. "10 WBTC") for MultiSend ERC-20 legs.
        if whitelistSymbol == nil || whitelistDecimals == nil {
            let cached = LatestBalancesCache.shared.retrieve(chainId: chain.id) ?? []
            if let tokenBalance = cached.first(where: { $0.address.caseInsensitiveCompare(token.checksummed) == .orderedSame }) {
                if whitelistSymbol == nil {
                    let trimmed = tokenBalance.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                    whitelistSymbol = trimmed.isEmpty ? nil : trimmed
                }
                if whitelistDecimals == nil {
                    whitelistDecimals = tokenBalance.decimals
                }
            }
        }
        
        return TokenMetadata(symbol: whitelistSymbol, decimals: whitelistDecimals)
    }
}

// MARK: - BatchLegResult

/// Rich decoded result for the main leg of a recognised multiSend batch.
struct BatchLegResult {
    /// Human-readable action label: "Compra", "Venta", "Inversión", "Rescate", or nil.
    let typeLabel: String?
    /// Formatted sent/sold amount with sign and symbol, e.g. "-1.008709 USDT".
    let sentAmount: String?
    /// Formatted received/bought amount with sign and symbol, e.g. "+0.000195 XAUt".
    let receivedAmount: String?
}

// MARK: - BatchLegTitleResolver

final class BatchLegTitleResolver {
    static let shared = BatchLegTitleResolver()

    // MARK: Known contract addresses (lower-cased) keyed by chain ID string.

    // Uniswap V3 SwapRouter
    private let uniswapV3Addresses: [String: String] = [
        "1": "0xe592427a0aece92de3edee1f18e0157c05861564"
    ]
    // Uniswap V2 Router02
    private let uniswapV2Addresses: [String: String] = [
        "1": "0x7a250d5630b4cf539739df2c5dacb4c659f2488d"
    ]
    // Aave V3 Pool
    private let aaveV3Addresses: [String: String] = [
        "1":     "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
        "137":   "0x794a61358d6845594f94dc1db02a252b5b4814ad",
        "42161": "0x794a61358d6845594f94dc1db02a252b5b4814ad",
        "10":    "0x794a61358d6845594f94dc1db02a252b5b4814ad",
        "43114": "0x794a61358d6845594f94dc1db02a252b5b4814ad"
    ]
    // Aave V2 LendingPool
    private let aaveV2Addresses: [String: String] = [
        "1": "0x7d2768de32b0b80b7a3454c06bdac9fa29ceecff"
    ]
    // CowSwap GPv2Settlement (same address across Ethereum, Gnosis, Polygon, etc.)
    private let cowSwapAddresses: [String: String] = [
        "1":   "0x9008d19f58aabd9ed0d60971565aa8510560ab41",
        "100": "0x9008d19f58aabd9ed0d60971565aa8510560ab41",
        "137": "0x9008d19f58aabd9ed0d60971565aa8510560ab41"
    ]

    private init() {}

    func isBatch(customInfo: SCGModels.TxInfo.Custom) -> Bool {
        normalizedMethod(customInfo.methodName) == "multisend"
    }

    func isBatch(details: SCGModels.TransactionDetails) -> Bool {
        if case let .custom(customInfo) = details.txInfo, isBatch(customInfo: customInfo) {
            return true
        }
        return normalizedMethod(details.txData?.dataDecoded?.method) == "multisend"
    }

    func mainLegTitle(from details: SCGModels.TransactionDetails) -> String? {
        guard isBatch(details: details),
              let multiSendActions = extractMultiSendActions(from: details),
              !multiSendActions.isEmpty
        else {
            return nil
        }

        // Always the one before the last (second-to-last action).
        let index = max(0, multiSendActions.count - 2)
        let mainLeg = multiSendActions[index]

        let method = normalizedMethod(mainLeg.dataDecoded?.method)
        // ERC-20 transfer → show "Envío" (outgoing from the safe)
        if method == "transfer" || (method == nil && mainLeg.data.map(isERC20TransferCalldata) == true) {
            return NSLocalizedString("ui_tx_send_title", comment: "Transaction type send title")
        }
        if let method = method {
            return method
        }
        return nil
    }

    /// Returns a rich `BatchLegResult` for recognized protocols (Uniswap, Aave, CowSwap).
    /// Returns `nil` when the batch is not recognized or token metadata is unavailable.
    func mainLegResult(from details: SCGModels.TransactionDetails, chainId: String) -> BatchLegResult? {
        guard isBatch(details: details),
              let actions = extractMultiSendActions(from: details),
              !actions.isEmpty
        else {
            return nil
        }

        // Scan all actions to find one targeting a known protocol address.
        // This is more robust than relying on positional heuristics (e.g. second-to-last),
        // since different protocols place their key action at different positions.
        for (index, action) in actions.enumerated() {
            let toAddress = action.to.description.lowercased()
            let method = normalizedMethod(action.dataDecoded?.method)

            if let knownAddress = uniswapV3Addresses[chainId], toAddress == knownAddress {
                return decodeUniswapV3(mainLeg: action, method: method, chainId: chainId)
            }

            if let knownAddress = uniswapV2Addresses[chainId], toAddress == knownAddress {
                return decodeUniswapV2(mainLeg: action, method: method, chainId: chainId)
            }

            if let knownAddress = aaveV3Addresses[chainId], toAddress == knownAddress {
                return decodeAave(mainLeg: action, method: method, version: 3, chainId: chainId)
            }

            if let knownAddress = aaveV2Addresses[chainId], toAddress == knownAddress {
                return decodeAave(mainLeg: action, method: method, version: 2, chainId: chainId)
            }

            if let knownAddress = cowSwapAddresses[chainId], toAddress == knownAddress {
                return decodeCowSwap(details: details, actions: actions, mainLegIndex: index, chainId: chainId)
            }
        }

        return nil
    }

    // MARK: - Private: Protocol decoders

    private func decodeUniswapV3(
        mainLeg: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx,
        method: String?,
        chainId: String
    ) -> BatchLegResult? {
        guard let params = mainLeg.dataDecoded?.parameters else { return nil }

        // The gateway wraps V3 struct params in a single parameter named "params".
        // Its type is either "tuple(...)" or a bare "(address,address,...)" parenthesised signature.
        // Extract positional values from it; fall back to flat named params for older responses.
        let tupleValues: [SCGModels.DataDecoded.Parameter.Value]?
        if let tupleParam = params.first(where: {
               $0.name == "params" && ($0.type.hasPrefix("tuple") || $0.type.hasPrefix("("))
           }),
           case .array(let arr) = tupleParam.value {
            tupleValues = arr
        } else {
            tupleValues = nil
        }

        switch method {
        case "exactinputsingle":
            // (tokenIn[0], tokenOut[1], fee[2], recipient[3], deadline[4], amountIn[5], amountOutMinimum[6], sqrtPriceLimitX96[7])
            let tokenIn: String?
            let tokenOut: String?
            let amountIn: UInt256?
            let amountOutMin: UInt256

            if let t = tupleValues {
                tokenIn     = addressValue(at: 0, in: t)
                tokenOut    = addressValue(at: 1, in: t)
                amountIn    = uint256Value(at: 5, in: t)
                amountOutMin = uint256Value(at: 6, in: t) ?? 0
            } else {
                tokenIn     = addressParam(named: "tokenIn",  in: params)
                tokenOut    = addressParam(named: "tokenOut", in: params)
                amountIn    = uint256Param(named: "amountIn", in: params)
                amountOutMin = uint256Param(named: "amountOutMinimum", in: params) ?? 0
            }
            guard let tokenIn, let tokenOut, let amountIn else { return nil }
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountIn,
                receivedToken: tokenOut, receivedAmount: amountOutMin,
                chainId: chainId
            )

        case "exactinput":
            // (path[0], recipient[1], deadline[2], amountIn[3], amountOutMinimum[4])
            let amountIn: UInt256?
            let amountOutMin: UInt256
            if let t = tupleValues {
                amountIn    = uint256Value(at: 3, in: t)
                amountOutMin = uint256Value(at: 4, in: t) ?? 0
            } else {
                amountIn    = uint256Param(named: "amountIn", in: params)
                amountOutMin = uint256Param(named: "amountOutMinimum", in: params) ?? 0
            }
            guard let amountIn else { return nil }
            let sentFormatted  = formattedAmount(amountIn, tokenAddress: nil, chainId: chainId, sign: "-")
            let recvFormatted  = formattedAmount(amountOutMin, tokenAddress: nil, chainId: chainId, sign: "+")
            return BatchLegResult(typeLabel: nil, sentAmount: sentFormatted, receivedAmount: recvFormatted)

        case "exactoutputsingle":
            // (tokenIn[0], tokenOut[1], fee[2], recipient[3], deadline[4], amountOut[5], amountInMaximum[6], sqrtPriceLimitX96[7])
            let tokenIn: String?
            let tokenOut: String?
            let amountOut: UInt256?
            let amountInMax: UInt256
            if let t = tupleValues {
                tokenIn    = addressValue(at: 0, in: t)
                tokenOut   = addressValue(at: 1, in: t)
                amountOut  = uint256Value(at: 5, in: t)
                amountInMax = uint256Value(at: 6, in: t) ?? 0
            } else {
                tokenIn    = addressParam(named: "tokenIn",  in: params)
                tokenOut   = addressParam(named: "tokenOut", in: params)
                amountOut  = uint256Param(named: "amountOut", in: params)
                amountInMax = uint256Param(named: "amountInMaximum", in: params) ?? 0
            }
            guard let tokenIn, let tokenOut, let amountOut else { return nil }
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountInMax,
                receivedToken: tokenOut, receivedAmount: amountOut,
                chainId: chainId
            )

        case "exactoutput":
            // (path[0], recipient[1], deadline[2], amountOut[3], amountInMaximum[4])
            let amountOut: UInt256?
            let amountInMax: UInt256
            if let t = tupleValues {
                amountOut  = uint256Value(at: 3, in: t)
                amountInMax = uint256Value(at: 4, in: t) ?? 0
            } else {
                amountOut  = uint256Param(named: "amountOut", in: params)
                amountInMax = uint256Param(named: "amountInMaximum", in: params) ?? 0
            }
            guard let amountOut else { return nil }
            let sentFormatted = formattedAmount(amountInMax, tokenAddress: nil, chainId: chainId, sign: "-")
            let recvFormatted = formattedAmount(amountOut, tokenAddress: nil, chainId: chainId, sign: "+")
            return BatchLegResult(typeLabel: nil, sentAmount: sentFormatted, receivedAmount: recvFormatted)

        default:
            return nil
        }
    }

    private func decodeUniswapV2(
        mainLeg: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx,
        method: String?,
        chainId: String
    ) -> BatchLegResult? {
        guard let params = mainLeg.dataDecoded?.parameters else { return nil }

        // All token-to-token V2 swaps share: amountIn/amountInMax at [0], path at [2].
        let pathValues: [SCGModels.DataDecoded.Parameter.Value]?
        if case .array(let arr) = params.first(where: { $0.name == "path" })?.value {
            pathValues = arr
        } else {
            pathValues = nil
        }
        let tokenIn: String?
        let tokenOut: String?
        if let path = pathValues, path.count >= 2,
           case .address(let addrIn) = path.first,
           case .address(let addrOut) = path.last {
            tokenIn  = addrIn.description.lowercased()
            tokenOut = addrOut.description.lowercased()
        } else {
            tokenIn  = nil
            tokenOut = nil
        }

        switch method {
        case "swapexacttokensfortokens":
            guard let amountIn = uint256Param(named: "amountIn", in: params) else { return nil }
            let amountOutMin = uint256Param(named: "amountOutMin", in: params) ?? 0
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountIn,
                receivedToken: tokenOut, receivedAmount: amountOutMin,
                chainId: chainId
            )

        case "swaptokensforexacttokens":
            guard let amountOut = uint256Param(named: "amountOut", in: params) else { return nil }
            let amountInMax = uint256Param(named: "amountInMax", in: params) ?? 0
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountInMax,
                receivedToken: tokenOut, receivedAmount: amountOut,
                chainId: chainId
            )

        case "swapexacttokensforeth":
            guard let amountIn = uint256Param(named: "amountIn", in: params) else { return nil }
            let amountOutMin = uint256Param(named: "amountOutMin", in: params) ?? 0
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountIn,
                receivedToken: tokenOut, receivedAmount: amountOutMin,
                chainId: chainId
            )

        case "swaptokensforexacteth":
            guard let amountOut = uint256Param(named: "amountOut", in: params) else { return nil }
            let amountInMax = uint256Param(named: "amountInMax", in: params) ?? 0
            return makeSwapResult(
                sentToken: tokenIn, sentAmount: amountInMax,
                receivedToken: tokenOut, receivedAmount: amountOut,
                chainId: chainId
            )

        default:
            return nil
        }
    }

    private func decodeAave(
        mainLeg: SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx,
        method: String?,
        version: Int,
        chainId: String
    ) -> BatchLegResult? {
        guard let params = mainLeg.dataDecoded?.parameters else { return nil }

        // supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        // withdraw(address asset, uint256 amount, address to)
        // deposit (Aave V2 alias for supply)
        // The gateway may also decode as "fallback" if it doesn't know the ABI —
        // in that case we still return nil (no result).
        let effectiveMethod = method ?? ""

        switch effectiveMethod {
        case "supply", "deposit":
            guard let asset  = addressParam(named: "asset",  in: params) ??
                               addressParam(named: "reserve", in: params),
                  let amount = uint256Param(named: "amount", in: params)
            else { return nil }

            let sentSymbol  = tokenSymbol(address: asset, chainId: chainId)
            let sentCategory = tokenCategory(address: asset, chainId: chainId)
            let aTokenSymbol = aTokenSymbolFor(underlyingSymbol: sentSymbol, chainId: chainId)

            let sentFormatted = formattedAmount(amount, tokenAddress: asset, chainId: chainId, sign: "-")
            let recvFormatted = formatRaw(amount: amount,
                                          symbol: aTokenSymbol ?? (sentSymbol.map { "a\($0)" }),
                                          decimals: tokenDecimals(address: asset, chainId: chainId),
                                          sign: "+")
            let typeLabel = aaveTypeLabel(sentCategory: sentCategory, receivedCategory: nil, isSent: true)
            return BatchLegResult(typeLabel: typeLabel, sentAmount: sentFormatted, receivedAmount: recvFormatted)

        case "withdraw":
            guard let asset  = addressParam(named: "asset",  in: params),
                  let amount = uint256Param(named: "amount", in: params)
            else { return nil }

            let recvSymbol    = tokenSymbol(address: asset, chainId: chainId)
            let recvCategory  = tokenCategory(address: asset, chainId: chainId)
            let aTokenSymbol  = aTokenSymbolFor(underlyingSymbol: recvSymbol, chainId: chainId)

            let sentFormatted = formatRaw(amount: amount,
                                          symbol: aTokenSymbol ?? (recvSymbol.map { "a\($0)" }),
                                          decimals: tokenDecimals(address: asset, chainId: chainId),
                                          sign: "-")
            let recvFormatted = formattedAmount(amount, tokenAddress: asset, chainId: chainId, sign: "+")
            let typeLabel = aaveTypeLabel(sentCategory: nil, receivedCategory: recvCategory, isSent: false)
            return BatchLegResult(typeLabel: typeLabel, sentAmount: sentFormatted, receivedAmount: recvFormatted)

        default:
            return nil
        }
    }

    /// Parses CowSwap setPreSignature calldata to extract buyToken (address) and buyAmount (uint256).
    /// CoW Protocol uses setPreSignature(bytes orderUid, bool signed), NOT an Order tuple — the
    /// orderUid is an opaque hash, so we cannot derive buyToken/buyAmount from it. We only attempt
    /// to parse when the calldata looks like a static Order tuple (first word after selector is an
    /// address-sized value, not the ABI offset 0x20 for dynamic bytes).
    private func parseCowSwapSetPreSignatureOrder(calldata: Data?) -> (buyTokenAddress: String, buyAmount: UInt256)? {
        let orderStart = 4  // after 4-byte selector
        let minLength = orderStart + 160  // need at least buyAmount at 128..160
        // #region agent log
        #if DEBUG
        let dataLen = calldata?.count ?? -1
        if calldata == nil || dataLen < minLength {
            tokenResolverAgentLog(location: "TokenMetadataResolver.swift:parseCowSwapSetPreSignatureOrder", message: "parse setPreSignature nil", hypothesisId: "A,B", data: ["calldataLength": dataLen, "minLength": minLength])
        }
        #endif
        // #endregion agent log
        guard let data = calldata, data.count >= minLength else { return nil }
        // CoW setPreSignature(bytes orderUid, bool signed): first word after selector is offset to bytes (0x20).
        // If so, we cannot parse as Order — return nil and use sent-only fallback.
        let firstWord = orderStart + 32
        if data.count >= firstWord {
            let offsetValue = data.subdata(in: orderStart..<firstWord)
            if offsetValue.count >= 31, offsetValue[31] == 0x20 {
                #if DEBUG
                tokenResolverAgentLog(location: "TokenMetadataResolver.swift:parseCowSwapSetPreSignatureOrder", message: "parse setPreSignature orderUid encoding", hypothesisId: "A", data: ["calldataLength": data.count])
                #endif
                return nil
            }
        }
        // buyToken = second 32-byte word, address right-padded → last 20 bytes of word at orderStart+32
        let buyTokenData = data.subdata(in: orderStart + 44..<orderStart + 64)
        let buyAmountData = data.subdata(in: orderStart + 128..<orderStart + 160)
        guard buyTokenData.count == 20 else {
            // #region agent log
            #if DEBUG
            tokenResolverAgentLog(location: "TokenMetadataResolver.swift:parseCowSwapSetPreSignatureOrder", message: "parse setPreSignature nil buyTokenData", hypothesisId: "A", data: ["buyTokenDataCount": buyTokenData.count])
            #endif
            // #endregion agent log
            return nil
        }
        guard let address = Address(buyTokenData) else {
            // #region agent log
            #if DEBUG
            tokenResolverAgentLog(location: "TokenMetadataResolver.swift:parseCowSwapSetPreSignatureOrder", message: "parse setPreSignature nil Address", hypothesisId: "A", data: ["buyTokenHex": buyTokenData.map { String(format: "%02x", $0) }.joined()])
            #endif
            // #endregion agent log
            return nil
        }
        let buyAmount = UInt256(buyAmountData)
        // #region agent log
        #if DEBUG
        tokenResolverAgentLog(location: "TokenMetadataResolver.swift:parseCowSwapSetPreSignatureOrder", message: "parse setPreSignature ok", hypothesisId: "A", data: ["buyToken": address.checksummed.lowercased(), "buyAmount": String(buyAmount), "calldataLength": data.count])
        #endif
        // #endregion agent log
        return (address.checksummed.lowercased(), buyAmount)
    }

    private func decodeCowSwap(
        details: SCGModels.TransactionDetails,
        actions: [SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx],
        mainLegIndex: Int,
        chainId: String
    ) -> BatchLegResult? {
        // The main leg is setPreSignature; the approve leg (one before the main) carries the sell token and sell amount.
        let approveLegIndex = mainLegIndex - 1
        guard approveLegIndex >= 0 else { return nil }
        let approveLeg = actions[approveLegIndex]
        let approveMethod = normalizedMethod(approveLeg.dataDecoded?.method)
        guard let approveParams = approveLeg.dataDecoded?.parameters,
              approveMethod == "approve"
        else { return nil }

        let sellTokenAddress = approveLeg.to.description.lowercased()
        guard let sellAmount = uint256Param(named: "_value", in: approveParams) ??
                               uint256Param(named: "amount", in: approveParams) ??
                               uint256Param(named: "value",  in: approveParams)
        else { return nil }

        // Parse the main leg (GPv2Settlement setPreSignature) calldata manually to avoid
        // the Solidity decoder's unsafeDowncast on nested tuples (Order), which can crash.
        // ABI: setPreSignature((order),bool) with static order → selector (4) + order fields inline.
        let mainLeg = actions[mainLegIndex]
        let mainLegDataCount = mainLeg.data?.data.count ?? -1
        // #region agent log
        #if DEBUG
        tokenResolverAgentLog(location: "TokenMetadataResolver.swift:decodeCowSwap", message: "decodeCowSwap entry", hypothesisId: "B,C", data: ["actionsCount": actions.count, "mainLegIndex": mainLegIndex, "approveLegIndex": approveLegIndex, "mainLegDataLength": mainLegDataCount])
        #endif
        // #endregion agent log
        if let (buyTokenString, buyAmount) = parseCowSwapSetPreSignatureOrder(calldata: mainLeg.data?.data) {
            // #region agent log
            #if DEBUG
            tokenResolverAgentLog(location: "TokenMetadataResolver.swift:decodeCowSwap", message: "decodeCowSwap path full", hypothesisId: "A", data: ["receivedToken": buyTokenString, "receivedAmount": String(buyAmount)])
            #endif
            // #endregion agent log
            return makeSwapResult(
                sentToken: sellTokenAddress,
                sentAmount: sellAmount,
                receivedToken: buyTokenString,
                receivedAmount: buyAmount,
                chainId: chainId
            )
        }

        if let receiveLeg = cowSwapFulfilledReceiveMovement(from: details),
           let receiveAmount = receiveLeg.value.flatMap({ UInt256($0) }) {
            let receivedTokenAddress = receiveLeg.tokenAddress?.lowercased()
            let sentFormatted = formattedAmount(sellAmount, tokenAddress: sellTokenAddress, chainId: chainId, sign: "-")
            let receivedFormatted =
                formattedAmount(receiveAmount, tokenAddress: receivedTokenAddress, chainId: chainId, sign: "+") ??
                formatRaw(amount: receiveAmount,
                          symbol: receiveLeg.tokenSymbol,
                          decimals: receiveLeg.decimals,
                          sign: "+")
            let sentCategory = tokenCategory(address: sellTokenAddress, chainId: chainId)
            let recvCategory = receivedTokenAddress.flatMap { tokenCategory(address: $0, chainId: chainId) }
            let typeLabel = uniswapCowTypeLabel(sentCategory: sentCategory, receivedCategory: recvCategory)
            return BatchLegResult(typeLabel: typeLabel, sentAmount: sentFormatted, receivedAmount: receivedFormatted)
        }

        // Fallback when setPreSignature cannot be decoded: show only sent amount.
        // #region agent log
        #if DEBUG
        tokenResolverAgentLog(location: "TokenMetadataResolver.swift:decodeCowSwap", message: "decodeCowSwap path fallback", hypothesisId: "A,B", data: ["sentOnly": true, "mainLegDataLength": mainLegDataCount])
        #endif
        // #endregion agent log
        let sellCategory = tokenCategory(address: sellTokenAddress, chainId: chainId)
        let sentFormatted = formattedAmount(sellAmount, tokenAddress: sellTokenAddress, chainId: chainId, sign: "-")
        let typeLabel = uniswapCowTypeLabel(sentCategory: sellCategory, receivedCategory: nil)
        return BatchLegResult(typeLabel: typeLabel, sentAmount: sentFormatted, receivedAmount: nil)
    }

    private func cowSwapFulfilledReceiveMovement(from details: SCGModels.TransactionDetails) -> SCGModels.TokenMovement? {
        let status = details.aconcagua?.cowSwap?.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isFulfilled = status == "fulfilled" || status == "filled" || status == "partiallyfilled"
        guard isFulfilled else { return nil }
        guard let receivingTokens = details.aconcagua?.tokenMovements?.receivingTokens, !receivingTokens.isEmpty else {
            return nil
        }
        return receivingTokens.first { movement in
            if let value = movement.value, let amount = UInt256(value) {
                return amount > 0
            }
            return false
        } ?? receivingTokens.first
    }

    // MARK: - Private: Type label helpers

    private func makeSwapResult(
        sentToken: String?,
        sentAmount: UInt256,
        receivedToken: String?,
        receivedAmount: UInt256,
        chainId: String
    ) -> BatchLegResult {
        let sentCategory = sentToken.flatMap { tokenCategory(address: $0, chainId: chainId) }
        let recvCategory = receivedToken.flatMap { tokenCategory(address: $0, chainId: chainId) }

        let typeLabel = uniswapCowTypeLabel(sentCategory: sentCategory, receivedCategory: recvCategory)
        let sentFormatted = formattedAmount(sentAmount, tokenAddress: sentToken, chainId: chainId, sign: "-")
        let recvFormatted = formattedAmount(receivedAmount, tokenAddress: receivedToken, chainId: chainId, sign: "+")

        return BatchLegResult(typeLabel: typeLabel, sentAmount: sentFormatted, receivedAmount: recvFormatted)
    }

    private func uniswapCowTypeLabel(sentCategory: String?, receivedCategory: String?) -> String? {
        if let cat = sentCategory, TokenCategory.isSavings(cat) {
            return NSLocalizedString("ui_tx_type_compra", comment: "Buy transaction type label")
        }
        if let cat = receivedCategory, TokenCategory.isSavings(cat) {
            return NSLocalizedString("ui_tx_type_venta", comment: "Sell transaction type label")
        }
        return nil
    }

    private func aaveTypeLabel(sentCategory: String?, receivedCategory: String?, isSent: Bool) -> String? {
        if isSent, let cat = sentCategory, TokenCategory.isSavings(cat) {
            return NSLocalizedString("ui_tx_type_inversion", comment: "Investment transaction type label")
        }
        if !isSent, let cat = receivedCategory, TokenCategory.isSavings(cat) {
            return NSLocalizedString("ui_tx_type_rescate", comment: "Redemption transaction type label")
        }
        return nil
    }

    // MARK: - Private: Token metadata helpers

    private func tokenSymbol(address: String, chainId: String) -> String? {
        guard let entry = TokenWhitelist.by(chainId: chainId, networkAddress: address) else { return nil }
        return entry.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenDecimals(address: String, chainId: String) -> Int? {
        guard let entry = TokenWhitelist.by(chainId: chainId, networkAddress: address) else { return nil }
        return Int(entry.decimals)
    }

    private func tokenCategory(address: String, chainId: String) -> String? {
        guard let entry = TokenWhitelist.by(chainId: chainId, networkAddress: address) else { return nil }
        return entry.tokenCategory
    }

    private func aTokenSymbolFor(underlyingSymbol: String?, chainId: String) -> String? {
        guard let symbol = underlyingSymbol else { return nil }
        let aSymbol = "a" + symbol.uppercased()
        if let _ = TokenWhitelist.aaveV3ReserveConfig(chainId: chainId, aTokenSymbolUpper: aSymbol) {
            return aSymbol
        }
        return nil
    }

    // MARK: - Private: Amount formatting

    /// Formats a raw `UInt256` token amount to a display string with sign and symbol.
    private func formattedAmount(
        _ amount: UInt256,
        tokenAddress: String?,
        chainId: String,
        sign: String
    ) -> String? {
        let symbol:   String?
        let decimals: Int?
        if let address = tokenAddress,
           let entry = TokenWhitelist.by(chainId: chainId, networkAddress: address) {
            symbol   = entry.tokenSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
            decimals = Int(entry.decimals)
        } else {
            symbol   = nil
            decimals = nil
        }
        return formatRaw(amount: amount, symbol: symbol, decimals: decimals, sign: sign)    }

    private func formatRaw(amount: UInt256, symbol: String?, decimals: Int?, sign: String) -> String? {
        guard amount > 0 else { return nil }
        // If the token isn't in the whitelist we have neither a reliable symbol nor decimals,
        // so omit rather than display a meaningless raw integer.
        guard let symbol, let decimals else { return nil }
        let decimalAmount = BigDecimal(Int256(amount), decimals)
        let formatted = TokenFormatter().string(
            from: decimalAmount,
            decimalSeparator: Locale.autoupdatingCurrent.decimalSeparator ?? ".",
            thousandSeparator: Locale.autoupdatingCurrent.groupingSeparator ?? ","
        )
        return sign + formatted + " " + symbol
    }

    // MARK: - Private: Parameter extraction helpers

    private func addressParam(named name: String, in params: [SCGModels.DataDecoded.Parameter]) -> String? {
        guard let param = params.first(where: { $0.name == name }),
              case .address(let addr) = param.value
        else { return nil }
        return addr.description.lowercased()
    }

    private func uint256Param(named name: String, in params: [SCGModels.DataDecoded.Parameter]) -> UInt256? {
        guard let param = params.first(where: { $0.name == name }),
              case .uint256(let val) = param.value
        else { return nil }
        return val.value
    }

    /// Extract an address string at a positional index from a decoded tuple array.
    private func addressValue(at index: Int, in values: [SCGModels.DataDecoded.Parameter.Value]) -> String? {
        guard index < values.count, case .address(let addr) = values[index] else { return nil }
        return addr.description.lowercased()
    }

    /// Extract a UInt256 at a positional index from a decoded tuple array.
    private func uint256Value(at index: Int, in values: [SCGModels.DataDecoded.Parameter.Value]) -> UInt256? {
        guard index < values.count, case .uint256(let val) = values[index] else { return nil }
        return val.value
    }

    // MARK: - Private: Generic helpers

    private func extractMultiSendActions(from details: SCGModels.TransactionDetails) -> [SCGModels.DataDecoded.Parameter.ValueDecoded.MultiSendTx]? {
        guard normalizedMethod(details.txData?.dataDecoded?.method) == "multisend",
              let firstParam = details.txData?.dataDecoded?.parameters?.first,
              firstParam.type == "bytes",
              case let .multiSend(actions)? = firstParam.valueDecoded
        else {
            return nil
        }
        return actions
    }

    private func normalizedMethod(_ method: String?) -> String? {
        guard let method = method?.trimmingCharacters(in: .whitespacesAndNewlines),
              !method.isEmpty
        else {
            return nil
        }
        return method.lowercased()
    }

    private func isERC20TransferCalldata(_ data: DataString) -> Bool {
        let bytes = data.data
        let selector = Data([0xA9, 0x05, 0x9C, 0xBB])
        return bytes.count >= 4 && bytes.prefix(4) == selector
    }
}
